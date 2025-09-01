#!/bin/bash
# Simple JupyterLab startup script inspired by Hearmeman24's approach

# Set workspace directory
WORKSPACE="${WORKSPACE:-/workspace}"

echo "Starting JupyterLab..."

# First make sure it's installed
if ! python -c "import jupyterlab" 2>/dev/null; then
    echo "Installing JupyterLab..."
    pip install jupyterlab
fi

# Start JupyterLab with simple settings
jupyter-lab \
    --ip=0.0.0.0 \
    --allow-root \
    --no-browser \
    --NotebookApp.token='' \
    --NotebookApp.password='' \
    --ServerApp.allow_origin='*' \
    --ServerApp.allow_credentials=True \
    --notebook-dir="$WORKSPACE" &

echo "JupyterLab started on port 8888"
