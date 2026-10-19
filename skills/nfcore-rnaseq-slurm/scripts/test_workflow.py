#!/usr/bin/env python3
"""Isolated behavioral checks; never contact S3 or submit Slurm tasks."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('workflow', Path(__file__).with_name('workflow.py'))
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)


class WorkflowTest(unittest.TestCase):
    def files(self, names):
        return [{'key': 'delivery/' + name, 'uri': 's3://bucket/delivery/' + name, 'size_bytes': 100} for name in names]

    def test_pair_lanes_and_single_end(self):
        m = [{'sample': 'A', 'condition': 'WT'}]
        r = w.pair_reads(self.files(['A/A_L001_R1_001.fastq.gz','A/A_L001_R2_001.fastq.gz',
                                    'A/A_L002_1.fq.gz','A/A_L002_2.fq.gz']),m)
        self.assertEqual(len(r),2)
        self.assertTrue(all(x['fastq_1'] != x['fastq_2'] for x in r))
        self.assertEqual(w.pair_reads(self.files(['A/A.fastq.gz']),m,True)[0]['fastq_2'],'')

    def test_missing_duplicate_and_identity(self):
        m = [{'sample': 'A', 'condition': 'WT'}]
        for names in [['A/A_R1.fastq.gz'],['A/A_R1.fastq.gz','A/A_R1.fastq.gz'],['B/B_R1.fastq.gz','B/B_R2.fastq.gz']]:
            with self.assertRaises(ValueError):w.pair_reads(self.files(names),m)
        with self.assertRaises(ValueError):w.pair_reads(self.files(['A/A_R1.fastq.gz','A/A_R2.fastq.gz']),m,True)

    def test_truncated_and_duplicate_inventory(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'inventory.json'
            p.write_text(json.dumps({'items': [],'truncated': True}))
            with self.assertRaises(ValueError):w.inventory('rustfs/bucket/delivery',p)
            item={'key':'delivery/A_R1.fq.gz','size_bytes':10,'is_dir':False}
            p.write_text(json.dumps({'items':[item,item],'truncated':False}))
            with self.assertRaises(ValueError):w.inventory('rustfs/bucket/delivery',p)

    def test_design_and_pairing(self):
        meta=[{'sample':f'{g}{i}','condition':g,'strain':'N4','subject':str(i)} for g in ['WT','KI'] for i in range(3)]
        c=[{'id':'ki_vs_wt','variable':'condition','reference':'WT','target':'KI','blocking':'subject'}]
        w.validate_contrasts(c,meta)
        meta[0]['strain']='D9L'
        with self.assertRaises(ValueError):w.validate_contrasts(c,meta)
        meta[0]['strain']='N4';meta[0]['subject']='other'
        with self.assertRaises(ValueError):w.validate_contrasts(c,meta)

    def test_matrix_identity_and_order(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'matrix.tsv';p.write_text('gene_id\tB\tA\ng1\t1\t2\n')
            m=[{'sample':'A'},{'sample':'B'}]
            self.assertEqual(w.matrix_samples(str(p),m),['B','A'])
            p.write_text('gene_id\tA\tA\n')
            with self.assertRaises(ValueError):w.matrix_samples(str(p),m)

    def test_profile_reuse_and_secret_filter(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);(root/'reports').mkdir()
            state={'run_dir':td,'project':td,'site_configs':['existing.config'],'explicit_site':True,'profiles':'site,apptainer',
                   'version':{'pipeline':'nf-core/rnaseq','commit':'abc'}}
            flat="process.executor = 'slurm'\nprocess.queue = 'compute'\naws.secretKey = 'TEST_SECRET'\n"
            with patch.object(w,'run',return_value=flat),contextlib.redirect_stdout(io.StringIO()):w.inspect(state)
            self.assertEqual(state['site_configs'],['existing.config'])
            self.assertNotIn('TEST_SECRET',(root/'reports/effective-config.txt').read_text())
            self.assertFalse((root/'site-slurm.config').exists())
            with patch.object(w,'run',return_value="process.executor = 'local'\n"):
                with self.assertRaises(ValueError):w.inspect(state)

    def test_fallback_and_selector_rejection(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);(root/'reports').mkdir()
            state={'run_dir':td,'project':td,'site_configs':[],'explicit_site':False,'partition':'compute','profiles':'apptainer',
                   'version':{'pipeline':'nf-core/rnaseq','commit':'abc'}}
            with patch.object(w,'run',side_effect=["process.executor = 'local'\n","process.executor = 'slurm'\n"]),contextlib.redirect_stdout(io.StringIO()):w.inspect(state)
            self.assertEqual(len(state['site_configs']),1)
            with patch.object(w,'run',return_value="process.executor = 'slurm'\nprocess.withName:X.executor = 'local'\n"):
                with self.assertRaises(ValueError):w.inspect(state)

    def test_latest_stable_and_no_fallback(self):
        response=io.BytesIO(b"manifest { nextflowVersion = '!>=25.10.0' }")
        with patch.object(w,'api',side_effect=[{'tag_name':'3.27.0','prerelease':False},{'sha':'123abc'}]),patch.object(w.urllib.request,'urlopen',return_value=response):
            v=w.resolve_version('rnaseq');self.assertEqual(v['tag'],'3.27.0');self.assertEqual(v['commit'],'123abc')
        with patch.object(w,'api',return_value={'tag_name':'dev','prerelease':True}):
            with self.assertRaises(ValueError):w.resolve_version('rnaseq')

    def test_three_independent_stage_roots(self):
        with tempfile.TemporaryDirectory() as td:
            d=Path(td);m=d/'meta.tsv';m.write_text('sample\tcondition\nA\tWT\nB\tWT\nC\tKI\nD\tKI\n')
            fa=d/'ref.fa';fa.write_text('>chr1\nACGT\n');gtf=d/'ref.gtf';gtf.write_text('chr1\tx\tgene\t1\t4\t.\t+\t.\tgene_id "g1"; gene "test";\n')
            reads=d/'reads.csv';w.write_table(reads,[{'sample':s,'fastq_1':f's3://bucket/{s}_R1.fq.gz','fastq_2':f's3://bucket/{s}_R2.fq.gz','strandedness':'auto'} for s in 'ABCD'],['sample','fastq_1','fastq_2','strandedness'],',')
            version={'pipeline':'nf-core/rnaseq','tag':'x','commit':'fixed','nextflow_requirement':'>=25'}
            args=['workflow.py','prepare','--stage','rnaseq','--project',td,'--study','bm','--date','20261019','--metadata',str(m),'--reads',str(reads),'--fasta',str(fa),'--gtf',str(gtf)]
            with patch('sys.argv',args),patch.object(w,'resolve_version',return_value=version),contextlib.redirect_stdout(io.StringIO()):w.main()
            r=d/'workflow/bm_rnaseq_20261019'
            before=(r/'versions.json').read_text()
            counts=r/'results/salmon.merged.gene_counts.tsv';counts.write_text('gene_id\tA\tB\tC\tD\ng1\t1\t1\t2\t2\n')
            lengths=r/'results/salmon.merged.gene_lengths.tsv';lengths.write_text('gene_id\tA\tB\tC\tD\ng1\t4\t4\t4\t4\n')
            contrasts=d/'contrasts.csv';contrasts.write_text('id,variable,reference,target,blocking\nki_vs_wt,condition,WT,KI,\n')
            args=['workflow.py','prepare','--stage','differentialabundance','--project',td,'--study','bm','--date','20261019','--metadata',str(m),'--upstream',str(r),'--gtf',str(gtf),'--contrasts',str(contrasts)]
            with patch('sys.argv',args),patch.object(w,'resolve_version',return_value=version),contextlib.redirect_stdout(io.StringIO()):w.main()
            de=d/'workflow/bm_differentialabundance_20261019'
            self.assertTrue(de.exists());self.assertEqual((r/'versions.json').read_text(),before)
            self.assertEqual(w.load(de/'params.json')['matrix'],str(counts))
            stats=d/'stats.tsv';stats.write_text('gene_id\tstat\tpvalue\ng1\t1\t0.3\n')
            ann=d/'ann.tsv';ann.write_text('gene_id\tdb_xref\ng1\tGeneID:1\n')
            manifest=d/'enrich.tsv';w.write_table(manifest,[{'id':'ki_vs_wt','results_tsv':str(counts),'annotation_tsv':str(ann),'stats_tsv':str(stats)}],['id','results_tsv','annotation_tsv','stats_tsv'])
            mapping=d/'mapping.tsv';mapping.write_text('term\tgene\nt1\t1\n')
            config=d/'annotation.json';w.save(config,{**{k:str(mapping) for k in ['go_term2gene','go_term2name','kegg_term2gene','kegg_term2name']},'id_type':'ncbi_geneid','provenance':'synthetic fixture'})
            args=['workflow.py','prepare','--stage','enrich','--project',td,'--study','bm','--date','20261019','--metadata',str(m),'--upstream',str(de),'--enrichment-manifest',str(manifest),'--annotation-config',str(config)]
            with patch('sys.argv',args),contextlib.redirect_stdout(io.StringIO()):w.main()
            self.assertTrue((d/'workflow/bm_DEG_enrich_20261019').exists())
            self.assertEqual(w.load(d/'workflow/bm_DEG_enrich_20261019/stage.json')['upstream'],str(de))


if __name__=='__main__':unittest.main()
