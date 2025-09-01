#!/bin/bash
# Simple JupyterLab startup based on Hearmeman24's approach

echo "Starting JupyterLab..."

# Ensure JupyterLab is installed
if ! python -c "import jupyterlab" 2>/dev/null; then
    echo "Installing JupyterLab..."
    pip install jupyterlab
fi

# Start JupyterLab
cd /workspace
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.token='' --NotebookApp.password='' &

echo "JupyterLab started on port 8888"
