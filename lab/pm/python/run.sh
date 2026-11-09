#!/bin/sh
# Runs inside a lab VM made from dy-base-dev: measures the Python package managers in phases, so the host can take a
# snapshot between them. The same requirements are installed with pip (in a venv), uv, Poetry and conda (Miniforge),
# each in its own project under ~/Projects; pipx installs two command-line tools.
#
# usage: sh run.sh <phase>
#   install-tools  uv (official installer), a uv-managed Python 3.12, Poetry and pipx as uv tools, Miniforge
#   workload       install the requirements in each project
#   cleanup-dry    print what each tool reports about its cache, without removing anything
#   cleanup        run each tool's own cache cleanup
#   recache        remove the caches, then install again to show what comes back
set -eu

work="$HOME/Projects"
reqs="numpy pandas scipy matplotlib scikit-learn requests flask django fastapi sqlalchemy pytest jupyterlab torch"
export PATH="$HOME/.local/bin:$HOME/miniforge3/bin:$PATH" UV_NO_PROGRESS=1 POETRY_NO_INTERACTION=1

# Installs the requirements in every project with its own tool; a failing tool is reported, not fatal.
install_all() {
    py=$(uv python find 3.12)
    (mkdir -p "$work/pip-app" && cd "$work/pip-app" && "$py" -m venv .venv && .venv/bin/pip install -q $reqs) || echo "pip install failed"
    (mkdir -p "$work/uv-app" && cd "$work/uv-app" && { [ -f pyproject.toml ] || uv init -q --python 3.12; } && uv add -q $reqs) || echo "uv add failed"
    (mkdir -p "$work/poetry-app" && cd "$work/poetry-app" && { [ -f pyproject.toml ] || poetry init -q --python ">=3.12,<3.13"; } \
        && poetry env use "$py" -q && poetry add -q $reqs) || echo "poetry add failed"
    conda create -y -q -n lab -c conda-forge python=3.12 numpy pandas scipy matplotlib scikit-learn requests flask \
        django fastapi sqlalchemy pytest jupyterlab pytorch > /dev/null || echo "conda create failed"
    pipx install -q black > /dev/null 2>&1 || echo "pipx black failed"
    pipx install -q httpie > /dev/null 2>&1 || echo "pipx httpie failed"
}

# Prints a folder's size in KB, or 0 if it does not exist.
size_kb() { if [ -e "$1" ]; then du -sk "$1" | cut -f1; else echo 0; fi; }

# Prints the sizes of every cache, store, environment and project folder.
report() {
    for d in "$HOME/Library/Caches/pip" "$HOME/.cache/uv" "$HOME/.local/share/uv/python" "$HOME/.local/share/uv/tools" \
             "$HOME/Library/Caches/pypoetry/cache" "$HOME/Library/Caches/pypoetry/artifacts" \
             "$HOME/Library/Caches/pypoetry/virtualenvs" "$HOME/.local/pipx" "$HOME/miniforge3/pkgs" "$HOME/miniforge3/envs" \
             "$work/pip-app/.venv" "$work/uv-app/.venv"; do
        printf '%10s KB  %s\n' "$(size_kb "$d")" "${d#$HOME/}"
    done
}

case ${1:?usage: run.sh <phase>} in
    install-tools)
        curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh > /tmp/uv.log 2>&1
        uv python install -q 3.12
        uv tool install -q poetry > /dev/null; uv tool install -q pipx > /dev/null
        curl -fsSL -o /tmp/miniforge.sh https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-MacOSX-arm64.sh
        bash /tmp/miniforge.sh -b -p "$HOME/miniforge3" > /tmp/miniforge.log 2>&1
        echo "uv $(uv -V | cut -d' ' -f2), python $(uv python find 3.12 | xargs -I{} {} -V | cut -d' ' -f2), $(poetry --version), pipx $(pipx --version), conda $(conda -V | cut -d' ' -f2)" ;;
    workload)
        install_all; echo "installed in 4 projects and 2 pipx tools" ;;
    cleanup-dry)
        (cd "$work/pip-app" && .venv/bin/pip cache info 2>&1 | tail -4)
        uv cache dir; poetry cache list; conda clean --all --dry-run 2>&1 | tail -4 ;;
    cleanup)
        (cd "$work/pip-app" && .venv/bin/pip cache purge 2>&1 | tail -1)
        uv cache prune 2>&1 | tail -1
        poetry cache clear --all -n PyPI 2>&1 | tail -1
        conda clean --all -y 2>&1 | tail -2 ;;
    recache)
        rm -rf "$HOME/Library/Caches/pip" "$HOME/.cache/uv" "$HOME/Library/Caches/pypoetry/cache" "$HOME/Library/Caches/pypoetry/artifacts"
        rm -rf "$work/pip-app/.venv" "$work/uv-app/.venv"
        install_all; echo "reinstalled"; "$work/uv-app/.venv/bin/python" -c "import numpy, pandas; print('uv-app imports numpy and pandas')" ;;
    *) echo "run.sh: unknown phase $1" >&2; exit 1 ;;
esac
report
