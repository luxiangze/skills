#!/usr/bin/env python3
"""Prepare independent nf-core/Slurm stages. Python standard library only."""
import argparse
import csv
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
STAGES = {'rnaseq': 'rnaseq', 'differentialabundance': 'differentialabundance', 'enrich': 'DEG_enrich'}


def run(cmd, **kwargs):
    return subprocess.run([str(x) for x in cmd], check=True, text=True, capture_output=True, **kwargs).stdout


def load(path):
    return json.loads(Path(path).read_text())


def save(path, data):
    path = Path(path)
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    tmp.replace(path)


def table(path):
    with Path(path).open(newline='') as f:
        first = f.readline()
        f.seek(0)
        return list(csv.DictReader(f, delimiter='\t' if '\t' in first else ','))


def write_table(path, rows, fields, sep='\t'):
    with Path(path).open('w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fields, delimiter=sep, extrasaction='ignore', lineterminator='\n')
        w.writeheader()
        w.writerows(rows)


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for b in iter(lambda: f.read(1024 * 1024), b''):
            h.update(b)
    return h.hexdigest()


def checked_file(value):
    p = Path(value).expanduser().resolve()
    if not p.is_file():
        raise ValueError(f'File missing: {p}')
    return str(p)


def safe(value):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', value):
        raise ValueError(f'Unsafe identifier: {value!r}')
    return value


def java_home(requested=None):
    if requested:
        path = Path(requested).expanduser().resolve()
        if not (path/'bin/java').is_file():
            raise ValueError('Requested JAVA_HOME has no bin/java')
        return str(path)
    if os.environ.get('JAVA_HOME') or shutil.which('java'):
        return None  # Preserve an existing environment/module choice.
    sdk = Path.home()/'.sdkman/candidates/java'
    for candidate in [sdk/'current', *sorted(sdk.glob('*'))]:
        release = candidate/'release'
        if not (candidate/'bin/java').is_file() or not release.is_file():
            continue
        match = re.search(r'JAVA_VERSION="(\d+)', release.read_text())
        if match and 17 <= int(match[1]) <= 25:
            return str(candidate.resolve())
    return None


def api(endpoint):
    if shutil.which('gh'):
        return json.loads(run(['gh', 'api', endpoint]))
    req = urllib.request.Request('https://api.github.com/' + endpoint,
                                 headers={'User-Agent': 'nfcore-rnaseq-slurm', 'Accept': 'application/vnd.github+json'})
    with urllib.request.urlopen(req, timeout=40) as r:
        return json.load(r)


def resolve_version(name, version=None):
    repo = f'nf-core/{name}'
    release = api(f'repos/{repo}/releases/' + ('tags/' + version if version else 'latest'))
    if release.get('draft') or release.get('prerelease'):
        raise ValueError('A stable, published release is required')
    tag = release['tag_name']
    commit = api(f'repos/{repo}/commits/{tag}')['sha']
    req = urllib.request.Request(f'https://raw.githubusercontent.com/{repo}/{commit}/nextflow.config',
                                 headers={'User-Agent': 'nfcore-rnaseq-slurm'})
    with urllib.request.urlopen(req, timeout=40) as r:
        config = r.read().decode()
    match = re.search(r"nextflowVersion\s*=\s*['\"]([^'\"]+)", config)
    if not match:
        raise ValueError('Cannot determine required Nextflow version from release manifest')
    return {'pipeline': repo, 'tag': tag, 'commit': commit, 'nextflow_requirement': match[1],
            'resolved_at': dt.datetime.now(dt.timezone.utc).isoformat()}


def source_parts(source):
    parts = source.strip('/').split('/', 2)
    if len(parts) < 2 or source.startswith('s3://'):
        raise ValueError('rc source must be alias/bucket[/prefix]')
    return parts[0], parts[1], (parts[2].rstrip('/') + '/') if len(parts) == 3 and parts[2] else ''


def inventory(source, snapshot=None):
    _, bucket, prefix = source_parts(source)
    data = load(snapshot) if snapshot else json.loads(run(['rc', 'ls', source, '--recursive', '--json']))
    if data.get('truncated') is not False or not isinstance(data.get('items'), list):
        raise ValueError('Listing must contain items and truncated=false; complete pagination first')
    keys = set()
    files = []
    for item in data['items']:
        key = item['key']
        if item.get('is_dir') or not key.startswith(prefix) or not re.search(r'\.(fastq|fq)(\.gz)?$', key, re.I):
            continue
        if Path(key).name.startswith('._'):
            continue
        if key in keys or int(item['size_bytes']) <= 0:
            raise ValueError(f'Duplicate or empty FASTQ: {key}')
        keys.add(key)
        files.append({'key': key, 'uri': f's3://{bucket}/{key}', 'size_bytes': item['size_bytes']})
    if not files:
        raise ValueError('No FASTQ objects under source prefix')
    return data, files


def metadata(path):
    rows = table(path)
    if not rows or not {'sample', 'condition'} <= rows[0].keys():
        raise ValueError('Metadata requires sample and condition columns')
    names = [r['sample'] for r in rows]
    if len(set(names)) != len(names):
        raise ValueError('Metadata must have one row per biological sample, not per lane')
    for r in rows:
        safe(r['sample'])
        if not r['condition']:
            raise ValueError('Empty condition')
    return rows


def pair_reads(files, meta, single=False):
    grouped = {}
    names = [r['sample'] for r in meta]
    for f in files:
        path = Path(f['key'])
        exact = [s for s in names if s in path.parts[:-1]]
        matches = exact or [s for s in names if path.name.startswith(s + '_') or path.name.startswith(s + '-')]
        if len(matches) != 1:
            raise ValueError(f'Cannot assign FASTQ unambiguously: {path}; supply --reads manifest')
        sample = matches[0]
        stem = re.sub(r'\.(fastq|fq)(\.gz)?$', '', path.name, flags=re.I)
        m = re.search(r'([_.-])R?([12])(?=([_.-]00[1-9])?$)', stem, re.I)
        if m:
            read = m[2]
            pair = str(path.parent / (stem[:m.start()] + '_READ' + stem[m.end():]))
        elif single:
            read, pair = '1', str(path)
        else:
            raise ValueError(f'Cannot identify read number: {path}; supply --reads manifest')
        if single and read == '2':
            raise ValueError('R2 found in single-end mode')
        slot = grouped.setdefault((sample, pair), {})
        if read in slot:
            raise ValueError(f'Duplicate R{read}: {sample}/{pair}')
        slot[read] = f['uri']
    rows = []
    for (sample, pair), reads in sorted(grouped.items()):
        expected = {'1'} if single else {'1', '2'}
        if reads.keys() != expected:
            raise ValueError(f'Missing mate for {sample}: {pair}')
        rows.append({'sample': sample, 'fastq_1': reads['1'], 'fastq_2': reads.get('2', ''), 'strandedness': 'auto'})
    validate_reads(rows, meta)
    return rows


def validate_reads(rows, meta):
    if {r['sample'] for r in rows} != {r['sample'] for r in meta}:
        raise ValueError('FASTQ sample set must exactly match metadata')
    seen = set()
    by_sample = {}
    for row in rows:
        if row.get('strandedness', 'auto') not in {'auto', 'forward', 'reverse', 'unstranded'}:
            raise ValueError('Invalid strandedness')
        paired = bool(row.get('fastq_2'))
        identity = (paired, row.get('strandedness', 'auto'))
        if row['sample'] in by_sample and by_sample[row['sample']] != identity:
            raise ValueError('Mixed library type or strandedness within one sample')
        by_sample[row['sample']] = identity
        for k in ['fastq_1', 'fastq_2']:
            uri = row.get(k, '')
            if k == 'fastq_1' and not uri:
                raise ValueError('Missing FASTQ_1')
            if uri:
                if uri in seen:
                    raise ValueError('FASTQ used more than once')
                seen.add(uri)
                if not uri.startswith('s3://'):
                    checked_file(uri)


def validate_contrasts(rows, meta):
    seen = set()
    for row in rows:
        for key in ['id', 'variable', 'reference', 'target']:
            if not row.get(key):
                raise ValueError(f'Contrast missing {key}')
        safe(row['id'])
        if row['id'] in seen or row['target'] == row['reference']:
            raise ValueError('Duplicate contrast or identical target/reference')
        seen.add(row['id'])
        var = row['variable']
        selected = [r for r in meta if r.get(var) in [row['target'], row['reference']]]
        for level in [row['target'], row['reference']]:
            if sum(r.get(var) == level for r in selected) < 2:
                raise ValueError('At least two biological replicates per group are required; recommend three or more')
        strains = {r.get('strain') for r in selected if r.get('strain')}
        if len(strains) > 1 and var != 'strain' and row.get('blocking') != 'strain':
            raise ValueError('Cross-strain contrast needs an explicit study-specific model; do not infer treatment effect')
        blocking = row.get('blocking', '')
        if blocking:
            if not all(r.get(blocking) for r in selected):
                raise ValueError('Blocking variable missing from sample metadata')
            blocks = {r[blocking] for r in selected}
            if any({r[var] for r in selected if r[blocking] == b} != {row['target'], row['reference']} for b in blocks):
                raise ValueError('Blocking is confounded or pairing incomplete; provide a reviewed custom design')
    if not rows:
        raise ValueError('No contrasts')


def reference_info(fasta, gtf):
    fasta, gtf = checked_file(fasta), checked_file(gtf)
    if Path(fasta).suffix == '.gz' or Path(gtf).suffix == '.gz':
        raise ValueError('Provide decompressed FASTA/GTF for validation and nf-core input')
    attrs, seqs = set(), set()
    with open(gtf) as f:
        for i, line in enumerate(f):
            if not line.startswith('#'):
                fields = line.rstrip().split('\t')
                if len(fields) != 9:
                    raise ValueError('Annotation must be GTF with nine columns')
                seqs.add(fields[0])
                attrs.update(re.findall(r'(\w+)\s+"[^"]*"', fields[8]))
            if i >= 20000:
                break
    if 'gene_id' not in attrs:
        raise ValueError('GTF has no gene_id attribute')
    fai = Path(fasta + '.fai')
    if fai.exists() and not seqs <= {ln.split('\t')[0] for ln in fai.read_text().splitlines()}:
        raise ValueError('GTF contigs absent from FASTA index')
    return {'fasta': fasta, 'gtf': gtf, 'attributes': sorted(attrs),
            'gene_name_attribute': 'gene_name' if 'gene_name' in attrs else ('gene' if 'gene' in attrs else 'gene_id'),
            'full_contig_validation': 'Use FASTA .fai or compute-node full check before execution'}


def matrix_samples(matrix, meta):
    with open(matrix) as f:
        cols = f.readline().rstrip('\n').split('\t')[1:]
    if len(cols) != len(set(cols)) or set(cols) != {r['sample'] for r in meta}:
        raise ValueError('Count matrix columns differ from biological sample metadata')
    return cols


def unique_file(root, pattern):
    found = sorted(Path(root).rglob(pattern))
    if len(found) != 1:
        raise ValueError(f'Expected one {pattern} in {root}, got {len(found)}; supply explicit paths')
    return str(found[0].resolve())


def prepare(a):
    project = Path(a.project).expanduser().resolve()
    name = safe(a.study) + '_' + STAGES[a.stage] + '_' + safe(a.date)
    if a.suffix:
        name += '_' + safe(a.suffix)
    dest = project / 'workflow' / name
    if dest.exists():
        raise ValueError('Stage exists; use submit --resume or choose --suffix')
    meta = metadata(a.metadata)
    manifests = {'metadata': checked_file(a.metadata)}
    state = {'stage': a.stage, 'project': str(project), 'run_dir': str(dest), 'study': a.study,
             'profiles': a.profiles or ('rnaseq,apptainer' if a.stage == 'differentialabundance' else 'apptainer'),
             'site_configs': [checked_file(p) for p in a.config], 'explicit_site': bool(a.config or a.profiles),
             'partition': safe(a.partition), 'max_cpus': a.max_cpus, 'max_memory_gb': a.max_memory_gb,
             'java_home': java_home(a.java_home), 'clear_proxy': a.clear_proxy, 'status': 'prepared',
             'resume_failures': 0, 'last_failure_cause': None, 'created_at': dt.datetime.now().astimezone().isoformat()}
    if a.max_cpus < 1 or a.max_memory_gb < 1:
        raise ValueError('CPU and memory limits must be positive')
    if (a.max_cpus > 32 or a.max_memory_gb > 64) and not a.authorized_large_resources:
        raise ValueError('Above 32 CPU/64 GB requires already-authorized --authorized-large-resources')
    rows, params, contrasts, listing = None, {}, None, None
    if a.stage != 'enrich':
        state['version'] = resolve_version(a.stage, a.pipeline_version)
    if a.stage == 'rnaseq':
        if a.reads:
            rows = table(a.reads)
            for r in rows:
                r.setdefault('fastq_2', '')
                r.setdefault('strandedness', 'auto')
            validate_reads(rows, meta)
            manifests['reads'] = checked_file(a.reads)
        else:
            listing, files = inventory(a.source, a.listing)
            rows = pair_reads(files, meta, a.single_end)
            state['source'] = a.source
        ref = reference_info(a.fasta, a.gtf)
        state['reference'] = ref
        manifests.update(gtf=ref['gtf'], fasta=ref['fasta'])
        params = {'input': str(dest/'samplesheet.csv'), 'outdir': str(dest/'results'), 'fasta': ref['fasta'],
                  'gtf': ref['gtf'], 'aligner': 'star_salmon', 'save_reference': True}
        if ref['gene_name_attribute'] != 'gene_name':
            params['gtf_extra_attributes'] = ref['gene_name_attribute']
        if not {'gene_biotype', 'gene_type', 'transcript_biotype'} & set(ref['attributes']):
            params['skip_biotype_qc'] = True
    elif a.stage == 'differentialabundance':
        upstream = str(Path(a.upstream).expanduser().resolve()) if a.upstream else None
        matrix = checked_file(a.matrix) if a.matrix else unique_file(upstream, 'salmon.merged.gene_counts.tsv')
        lengths = checked_file(a.lengths) if a.lengths else unique_file(upstream, 'salmon.merged.gene_lengths.tsv')
        if matrix_samples(matrix, meta) != matrix_samples(lengths, meta):
            raise ValueError('Counts and length matrix sample order differs')
        contrasts = table(a.contrasts)
        validate_contrasts(contrasts, meta)
        gtf = checked_file(a.gtf)
        manifests.update(matrix=matrix, lengths=lengths, contrasts=checked_file(a.contrasts), gtf=gtf)
        state['upstream'] = upstream
        state['r_env'] = str(Path(a.r_env).expanduser().resolve()) if a.r_env else str(dest/'r_env')
        attrs = set()
        with open(gtf) as stream:
            for i, line in enumerate(stream):
                if not line.startswith('#'):
                    attrs.update(re.findall(r'(\w+)\s+"[^"]*"', line))
                if i >= 20000:
                    break
        gene_name = 'gene_name' if 'gene_name' in attrs else ('gene' if 'gene' in attrs else 'gene_id')
        params = {'study_name': name, 'input': str(dest/'metadata.csv'), 'contrasts': str(dest/'contrasts.csv'),
                  'matrix': matrix, 'feature_length_matrix': lengths, 'gtf': gtf, 'outdir': str(dest/'results'),
                  'differential_method': 'deseq2', 'deseq2_alpha': .05, 'differential_min_fold_change': 2,
                  'differential_max_qval': .05, 'differential_subset_to_contrast_samples': True,
                  'features_gtf_feature_type': 'gene', 'features_gtf_table_first_field': 'gene_id',
                  'features_name_col': gene_name,
                  'features_metadata_cols': ','.join(k for k in ['gene_id', 'gene_name', 'gene', 'description', 'db_xref', 'gene_biotype'] if k in attrs)}
        state['contrasts'] = contrasts
    else:
        upstream = Path(a.upstream).expanduser().resolve()
        manifest = checked_file(a.enrichment_manifest)
        annotations = checked_file(a.annotation_config)
        validate_enrichment_inputs(table(manifest), load(annotations))
        manifests.update(enrichment_manifest=manifest, annotation_config=annotations)
        for row in table(manifest):
            for key in ['results_tsv', 'annotation_tsv', 'stats_tsv']:
                manifests[row['id'] + '_' + key] = checked_file(row[key])
        annotation = load(annotations)
        for key in ['go_term2gene', 'go_term2name', 'kegg_term2gene', 'kegg_term2name', 'id_map']:
            if key in annotation:
                manifests[key] = checked_file(annotation[key])
        state.update(upstream=str(upstream), enrichment_manifest=manifest, annotation_config=annotations,
                     r_env=str(Path(a.r_env).expanduser().resolve()) if a.r_env else str(dest/'r_env'))
    if a.params:
        extra = load(a.params)
        forbidden = {'input', 'outdir', 'matrix', 'feature_length_matrix', 'contrasts', 'study_name'} & extra.keys()
        if forbidden:
            raise ValueError(f'Use explicit stage inputs instead of overriding {sorted(forbidden)}')
        params.update(extra)
    dest.mkdir(parents=True)
    for directory in ['logs', 'reports', 'work', 'results', 'runtime/scripts', 'runtime/assets']:
        (dest/directory).mkdir(parents=True, exist_ok=True)
    for folder in ['scripts', 'assets']:
        for p in (ROOT/folder).iterdir():
            if p.is_file():
                shutil.copy2(p, dest/'runtime'/folder/p.name)
    write_table(dest/'metadata.tsv', meta, list(meta[0]))
    write_table(dest/'metadata.csv', meta, list(meta[0]), ',')
    if rows is not None:
        write_table(dest/'samplesheet.csv', rows, ['sample', 'fastq_1', 'fastq_2', 'strandedness'], ',')
    if listing is not None:
        save(dest/'inventory.json', listing)
    if contrasts is not None:
        write_table(dest/'contrasts.csv', contrasts, list(dict.fromkeys(k for r in contrasts for k in r)), ',')
    save(dest/'params.json', params)
    save(dest/'inputs.json', {k: {'path': p, 'sha256': digest(p)} for k, p in manifests.items()})
    if a.stage != 'enrich':
        save(dest/'versions.json', state['version'])
        (dest/'resources.config').write_text(
            f'process.resourceLimits = [cpus: {a.max_cpus}, memory: {a.max_memory_gb}.GB]\n')
    save(dest/'stage.json', state)
    script = '\n'.join(['#!/bin/bash -l', f'#SBATCH --job-name={name}', f'#SBATCH --partition={a.partition}',
                         '#SBATCH --cpus-per-task=2', '#SBATCH --mem=8G', '#SBATCH --time=7-00:00:00',
                         f'#SBATCH --output={shlex.quote(str(dest/"logs/driver-%j.out"))}',
                         f'#SBATCH --error={shlex.quote(str(dest/"logs/driver-%j.err"))}',
                         'set -Eeuo pipefail', f'cd {shlex.quote(str(dest))}',
                         f'exec python3 {shlex.quote(str(dest/"runtime/scripts/workflow.py"))} execute --run-dir {shlex.quote(str(dest))} "$@"', ''])
    (dest/'run.sbatch').write_text(script)
    (dest/'.gitignore').write_text('work/\n.nextflow/\n.nextflow.log*\nr_env/.pixi/\nr_env/renv/library/\n')
    print(dest)


def validate_enrichment_inputs(rows, annotation):
    if not rows or not {'id', 'results_tsv', 'annotation_tsv', 'stats_tsv'} <= rows[0].keys():
        raise ValueError('Enrichment manifest needs id, results_tsv, annotation_tsv, stats_tsv')
    ids = set()
    for row in rows:
        safe(row['id'])
        if row['id'] in ids:
            raise ValueError('Duplicate enrichment contrast id')
        ids.add(row['id'])
        for key in ['results_tsv', 'annotation_tsv', 'stats_tsv']:
            checked_file(row[key])
        if 'stat' not in table(row['stats_tsv'])[0]:
            raise ValueError('Original DESeq2 stat column required')
    if not all(key in annotation for key in ['go_term2gene', 'go_term2name', 'kegg_term2gene', 'kegg_term2name', 'id_type', 'provenance']):
        raise ValueError('Annotation config must define four mapping tables, id_type and provenance')
    for key in ['go_term2gene', 'go_term2name', 'kegg_term2gene', 'kegg_term2name']:
        checked_file(annotation[key])


def config_command(state):
    v = state['version']
    configs = [str(Path(state['run_dir'])/'resources.config'), *state['site_configs']]
    if any(',' in p for p in configs):
        raise ValueError('Nextflow config paths cannot contain commas')
    return ['nextflow', '-c', ','.join(configs), 'config', v['pipeline'], '-r', v['commit'],
            '-profile', state['profiles'], '-flat']


def inspect(state):
    flat = run(config_command(state), env=execution_env(state))
    executors = re.findall(r"(?m)^([^\n=]*executor)\s*=\s*['\"]?([A-Za-z]+)", flat)
    base = next((value for key, value in executors if key.strip() == 'process.executor'), 'local')
    if base != 'slurm':
        if state['explicit_site']:
            raise ValueError('Supplied profiles/config do not select Slurm; correct site configuration')
        fallback = Path(state['run_dir'])/'site-slurm.config'
        fallback.write_text(f"process.executor = 'slurm'\nprocess.queue = '{state['partition']}'\nexecutor.queueSize = 12\n")
        state['site_configs'].append(str(fallback))
        save(Path(state['run_dir'])/'stage.json', state)
        flat = run(config_command(state), env=execution_env(state))
        executors = re.findall(r"(?m)^([^\n=]*executor)\s*=\s*['\"]?([A-Za-z]+)", flat)
        base = next((value for key, value in executors if key.strip() == 'process.executor'), 'local')
    # Any explicit local selectors need deliberate review: they may run on the driver.
    if base != 'slurm' or any(value != 'slurm' for _, value in executors):
        raise ValueError('Non-Slurm process executor detected; review selectors before submission')
    allowed = re.compile(r'(?i)(executor|queue|resourceLimits|apptainer.enabled|singularity.enabled|docker.enabled)')
    selected = [line for line in flat.splitlines() if allowed.search(line.split('=')[0])
                and not re.search(r'(?i)(aws|secret|password|token|access.?key)', line)]
    (Path(state['run_dir'])/'reports/effective-config.txt').write_text('\n'.join(selected) + '\n')
    state['config_verified'] = True
    save(Path(state['run_dir'])/'stage.json', state)
    print('\n'.join(selected))


def execution_env(state):
    env = os.environ.copy()
    if state.get('java_home'):
        env['JAVA_HOME'] = state['java_home']
        env['PATH'] = state['java_home'] + '/bin:' + env['PATH']
    if state.get('clear_proxy'):
        for key in ['http_proxy', 'https_proxy', 'all_proxy', 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY']:
            env.pop(key, None)
    env['NXF_ANSI_LOG'] = 'false'
    env.setdefault('NXF_APPTAINER_CACHEDIR', str(Path(state['project'])/'.cache/apptainer'))
    return env


def execute(state, resume=False):
    root = Path(state['run_dir'])
    if os.environ.get('SLURM_JOB_ID'):
        state['job_id'] = os.environ['SLURM_JOB_ID']
    if state['stage'] == 'enrich':
        env = Path(state['r_env'])
        if not (env/'renv/activate.R').exists():
            subprocess.run(['bash', str(root/'runtime/scripts/setup_r.sh'), str(env)], check=True, env=execution_env(state))
        cmd = ['pixi', 'run', '--manifest-path', str(env/'pixi.toml'), '-e', 'r', 'Rscript',
               str(root/'runtime/scripts/enrich.R'), state['enrichment_manifest'], state['annotation_config'], str(root)]
        cwd = env
    else:
        if not state.get('config_verified'):
            raise ValueError('Run inspect-config before submitting')
        v = state['version']
        stamp = os.environ.get('SLURM_JOB_ID', dt.datetime.now().strftime('%Y%m%d%H%M%S'))
        cmd = ['nextflow', '-log', str(root/f'logs/nextflow-{stamp}.log'),
               '-c', ','.join([str(root/'resources.config'), *state['site_configs']]), 'run', v['pipeline'], '-r', v['commit'],
               '-profile', state['profiles'], '-params-file', str(root/'params.json'),
               '-work-dir', str(root/'work'), '-with-report', str(root/f'reports/run-{stamp}.html'),
               '-with-timeline', str(root/f'reports/timeline-{stamp}.html'), '-with-trace', str(root/f'reports/trace-{stamp}.tsv')]
        if resume:
            cmd.append('-resume')
        cwd = root
    state['status'] = 'running'
    save(root/'stage.json', state)
    try:
        subprocess.run(cmd, cwd=cwd, env=execution_env(state), check=True)
        if state['stage'] == 'differentialabundance':
            state['status'] = 'pipeline_complete_stats_pending'
            save(root/'stage.json', state)
            env = Path(state['r_env'])
            subprocess.run(['bash', str(root/'runtime/scripts/setup_r.sh'), str(env), '--deseq2'], check=True, env=execution_env(state))
            subprocess.run(['pixi', 'run', '--manifest-path', str(env/'pixi.toml'), '-e', 'r', 'Rscript',
                            str(root/'runtime/scripts/export_stats.R'), str(root)], cwd=env, check=True, env=execution_env(state))
            state['status'] = 'completed'
        else:
            state['status'] = 'completed'
    except subprocess.CalledProcessError:
        state['status'] = 'failed'
        if resume:
            state['resume_failures'] += 1
        raise
    finally:
        save(root/'stage.json', state)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='command', required=True)
    inv = sub.add_parser('inventory')
    inv.add_argument('--source', required=True)
    inv.add_argument('--out', required=True)
    prep = sub.add_parser('prepare')
    prep.add_argument('--stage', choices=STAGES, required=True)
    prep.add_argument('--project', default='.')
    prep.add_argument('--study', required=True)
    prep.add_argument('--date', default=dt.date.today().strftime('%Y%m%d'))
    prep.add_argument('--suffix', default='')
    prep.add_argument('--metadata', required=True)
    for key in ['source', 'listing', 'reads', 'fasta', 'gtf', 'upstream', 'matrix', 'lengths', 'contrasts',
                'params', 'pipeline-version', 'profiles', 'java-home', 'enrichment-manifest', 'annotation-config', 'r-env']:
        prep.add_argument('--' + key)
    prep.add_argument('--config', action='append', default=[])
    prep.add_argument('--partition', default='compute')
    prep.add_argument('--max-cpus', type=int, default=32)
    prep.add_argument('--max-memory-gb', type=int, default=64)
    prep.add_argument('--authorized-large-resources', action='store_true')
    prep.add_argument('--single-end', action='store_true')
    prep.add_argument('--clear-proxy', action='store_true')
    for name in ['inspect-config', 'submit', 'execute', 'status', 'collect']:
        cmd = sub.add_parser(name)
        cmd.add_argument('--run-dir', required=True)
        if name in ['submit', 'execute']:
            cmd.add_argument('--resume', action='store_true')
    a = p.parse_args()
    if a.command == 'inventory':
        data, files = inventory(a.source)
        save(a.out, data)
        print(f'{len(files)} FASTQ objects')
    elif a.command == 'prepare':
        prepare(a)
    else:
        root = Path(a.run_dir).expanduser().resolve()
        state = load(root/'stage.json')
        if a.command == 'inspect-config':
            if state['stage'] == 'enrich':
                raise ValueError('Enrichment is an R Slurm job, not a Nextflow pipeline')
            inspect(state)
        elif a.command == 'execute':
            execute(state, a.resume)
        elif a.command == 'submit':
            if state.get('job_id'):
                active = run(['squeue', '-h', '-j', state['job_id'], '-o', '%T']).strip()
                if active:
                    raise ValueError(f'Existing job still active: {state["job_id"]} {active}')
            if a.resume and state['resume_failures'] >= 2:
                raise ValueError('Two failed resumes: review failure cause before further action')
            if state['stage'] != 'enrich':
                inspect(state)
            cmd = ['sbatch', '--parsable', str(root/'run.sbatch')]
            if a.resume:
                cmd.append('--resume')
            job = run(cmd).strip().split(';')[0]
            if not job.isdigit():
                raise ValueError('Unexpected sbatch job id')
            state.update(job_id=job, status='submitted')
            save(root/'stage.json', state)
            print(job)
        elif a.command == 'status':
            print(json.dumps(state, ensure_ascii=False, indent=2))
            if state.get('job_id'):
                print(run(['sacct', '-j', state['job_id'], '--format=JobID,State,ExitCode,Elapsed,AllocCPUS,ReqMem', '-P']))
        else:
            results = sorted(str(x.relative_to(root)) for x in (root/'results').rglob('*') if x.is_file())
            save(root/'reports/artifacts.json', {'stage': state['stage'], 'status': state['status'], 'files': results})
            summary = root/'results/summary.tsv'
            deg = root/'results/original_stats/DEG_summary.tsv'
            lines = [f'# {root.name} 结果摘要', '', f'阶段：{state["stage"]}；状态：{state["status"]}。', '',
                     '下列计数来自保存的结果表；提交成功不代表分析完成。', '']
            if deg.exists():
                for row in table(deg):
                    lines.append(f'- {row["id"]}：上调 {row["up"]}，下调 {row["down"]}，合计 {row["total"]}。')
            if summary.exists():
                for row in table(summary):
                    lines.append(f'- {row["id"]} / {row["database"]} / {row["method"]} / {row["direction"]}：显著 {row["significant"]} 项。')
            lines += ['', '## 验收记录', '', '- RNA-seq：人工记录 MultiQC、比对、链特异性、PCA 和样本身份核查结论。',
                      '- 差异分析：核对比较设计、批次/配对、上游矩阵及原始 Wald 统计量。',
                      '- 富集：见 mapping_summary.tsv 和 methods.json，核对 ID 映射、背景与注释版本。',
                      '- 重要限制：富集代表基因集合的统计关联，不直接证明通路活性或因果关系。', '',
                      '完整产物索引：artifacts.json。']
            (root/'reports/summary_zh.md').write_text('\n'.join(lines)+'\n')
            print(f'{state["status"]}: {len(results)} result files; inspect QC and summaries before reporting completion')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError, IndexError, subprocess.CalledProcessError) as e:
        # Do not echo subprocess stderr: Nextflow may include resolved credential values.
        print('ERROR: ' + (f'Command failed: {Path(e.cmd[0]).name}' if isinstance(e, subprocess.CalledProcessError) else str(e)), file=sys.stderr)
        sys.exit(2)
