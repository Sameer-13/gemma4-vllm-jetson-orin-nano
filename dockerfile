# Use the official Ubuntu base image
FROM ubuntu:22.04

# Set environment variables to avoid user interaction during installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        build-essential \
        git \
        wget \
        curl \
        ca-certificates \
        libssl-dev \
        libffi-dev \
        iputils-ping \
        && rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /app

# Copy all files from the current directory to the container
COPY . /app

# Install Miniconda
RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh && \
    bash /tmp/miniconda.sh -b -p /opt/conda && \
    rm /tmp/miniconda.sh && \
    /opt/conda/bin/conda clean -afy

ENV PATH="/opt/conda/bin:$PATH"

# Accept Anaconda TOS for required channels
RUN conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r

# Add conda-forge channel and set channel priority
RUN conda config --add channels conda-forge && \
    conda config --set channel_priority strict && \
    conda update -n base -c defaults conda

# Optional: test network connectivity to conda-forge
RUN ping -c 3 conda.anaconda.org

# Create conda environment from environment.yml
RUN conda env create -f environment.yml

# Initialize conda for bash so activation works in all shells
RUN /opt/conda/bin/conda init bash

# Set bash as the default shell for all subsequent RUN/CMD/ENTRYPOINT
SHELL ["/bin/bash", "-c"]

# Activate the environment by default in every shell
RUN echo "conda activate vllm-env" >> ~/.bashrc

# Run vLLM server when container starts
CMD ["--model", "majentik/gemma-4-E2B-it-TurboQuant-AWQ-4bit", "--host", "0.0.0.0", "--port", "8000", "--max-model-len", "10000", "--gpu-memory-utilization", "0.9", "--quantization", "awq", "--reasoning-parser", "gemma4", "--tool-call-parser", "gemma4", "--enable-auto-tool-choice", "--limit-mm-per-prompt","image=4,audio=1", "--async-scheduling", "--mm-processor-kwargs", '{"max_soft_tokens": 1120}', "--chat-template", "examples tool_chat_template_gemma4.jinja", "--max-num-seqs", "2",]