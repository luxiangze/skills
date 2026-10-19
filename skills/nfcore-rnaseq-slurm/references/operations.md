# Site checks, recovery, and skill updates

## Before submission

Inspect `$NXF_HOME/config` (default `~/.nextflow/config`), launch directory config,
selected pipeline profiles and explicit `-c` files. Never print resolved AWS or
credential settings. `-C` replaces normal config discovery and can disable the
user's S3 setup; use it only for a deliberately isolated configuration.

`inspect-config` captures `nextflow config ... -flat` privately, exports only
executor/resource/container switches and refuses non-Slurm executor selectors.
Some workflows deliberately contain local selectors: review their role and adapt
explicitly rather than allowing hidden computation on login/driver nodes.

Resolve Nextflow/Java compatibility from the locked release manifest and official
Nextflow runtime docs. Preserve the existing installation unless a compatible
replacement is necessary and authorized. S3 rc and Nextflow use different clients
and may use different credentials. Check a small known object through Nextflow
on a compute node and verify shared reference/work/container storage.

On this cluster inspect `sinfo`, `scontrol show partition`, and cgroup memory
configuration before setting resources. Login-shell Slurm scripts allow module
loading. No blanket module purge, no guessed module versions, and no global proxy
or credential edits. The supplied driver's 2 CPU/8 GB/7 day request is a template;
adapt time to partition limits and measured driver needs.

## Recovery

- Inspect driver log, Nextflow log, `.command.err`, `.command.sh`, trace, and sacct
  state. OUT_OF_MEMORY, input errors and authentication failures need different
  fixes. Never fix S3 access by copying keys between aliases.
- Resume the same run directory and revision; save the cause and correction in
  reports/recovery.md. Two failures with the same cause stop automatic resumes.
- A new experimental design gets a new differential stage pointing to the old RNA
  stage. New enrichment annotation gets a new enrichment stage. Neither requires
  rerunning earlier FASTQ processing.
- Do not claim completion from sbatch's exit status. Check driver state, Nextflow
  completion/trace and expected artifacts; fill the Chinese QC summary.
- Keep cache/work until results have been accepted. Do not run nextflow clean,
  delete object storage data, upload data, or cancel unrelated jobs automatically.

## Update this skill

Canonical source is `~/skills/skills/nfcore-rnaseq-slurm` in the user's skills Git
catalogue. With Skills Manager installed, resolve its current CLI as prescribed
by the manage-skills skill, then run commands serially:

```text
skills-manager-cli skills update nfcore-rnaseq-slurm
skills-manager-cli skills deploy nfcore-rnaseq-slurm --agent codex
skills-manager-cli --json skills status nfcore-rnaseq-slurm
```

Local-source updates reimport canonical source. Commit only this skill and its
catalogue entry, preserve unrelated changes, and follow the repository's release
contract. Do not use global preset sync to deploy one skill. Installing in another
environment: `gh skill install luxiangze/skills nfcore-rnaseq-slurm`.
