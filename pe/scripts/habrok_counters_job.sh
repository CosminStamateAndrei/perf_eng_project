#!/bin/bash
#SBATCH --job-name=gapbs-counters
#SBATCH --partition=regular
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --mem=120G
#SBATCH --time=01:30:00
#SBATCH --output=gapbs-counters-%j.out

set -u
cd "${SLURM_SUBMIT_DIR:-.}"
P=$HOME/opt/papi
export PATH=$P/bin:$PATH
export CPATH=$P/include${CPATH:+:$CPATH}
export LIBRARY_PATH=$P/lib${LIBRARY_PATH:+:$LIBRARY_PATH}
export LD_LIBRARY_PATH=$P/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

echo "node $(hostname), $(nproc) CPUs, papi: $(command -v papi_avail || echo missing)"
papi_avail 2>&1 | grep -E 'PAPI version|Number Hardware Counters|PAPI_TOT_CYC|PAPI_L2_DCM|PAPI_L3_TCM'

ONLY=${ONLY:-"sysinfo build verify timers counters_base known_answer papi mlp o1_compiler o3_hugepages o4_prefetch o5_relabel big_graph o6_first_touch package"} \
NO_TIMING=1 MACHINE=habrok SKIP_APT=1 SET_SYS=0 bash pe/scripts/batch_all.sh
