#!/bin/bash
# Simple JupyterLab startup based on Hearmeman24's approach

echo "Starting JupyterLab..."

# Check if jupyter command exists instead of Python module
if ! command -v jupyter &> /dev/null; then
    echo "Installing JupyterLab..."
    pip install jupyterlab
fi

# Start JupyterLab in workspace
cd /workspace

# Check if already running
if pgrep -f "jupyter-lab" > /dev/null; then
    echo "JupyterLab is already running"
else
    echo "Starting JupyterLab on port 8888..."
    nohup jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.token='' --NotebookApp.password='' --ServerApp.allow_origin='*' --ServerApp.allow_credentials=True > /workspace/jupyter.log 2>&1 &
    sleep 2
    echo "JupyterLab started on port 8888"
fi
