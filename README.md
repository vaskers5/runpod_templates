# RunPod Templates

A collection of useful setup scripts and templates for RunPod servers.

## Overview

This repository contains pre-configured templates and automation scripts to help you quickly set up and deploy various environments on RunPod cloud infrastructure.

## Features

- Quick server setup scripts
- Pre-configured development environments
- GPU-optimized configurations
- Common ML/AI frameworks templates
- Network and storage configuration helpers
- Automatic S3 mounting script

## Usage

1. Clone this repository to your RunPod instance
2. Choose the appropriate template for your use case
3. Run the setup script
4. Start developing!

## Templates Available

- Basic development environment
- Machine learning setup (PyTorch, TensorFlow)
- Data science stack (Jupyter, pandas, numpy)
- Web development environment
- Custom GPU configurations
- ComfyUI environment setup

## Contributing

Feel free to submit pull requests with additional templates or improvements to existing ones.

## License

MIT License - see LICENSE file for details.

overall_pod_template:
image: runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu22.04
start command copy from 'extra_command'
container: 200gb
volume: 1024gb
volume mount path
http ports:
8001: 21
8002: 20
tcp ports: 
8003 22
```shell
ENV_VARIABLES:
S3__ACCESS_KEY=
S3__SECRET_KEY=
S3__ENDPOINT_URL=
S3_BUCKET=
S3_MOUNT_POINT=
ADMIN_USER_NAME=
ADMIN_USER_PUBKEY=
ADMIN_USER_SUDO=
ADMIN_USERS=
GITHUB_TOKEN=
PYTHON_VERSION=3.12
ADMIN_USERS="alice:ssh-ed25519 AAAAB3Nza...:true;bob:ssh-ed25519 AAAAB3Nza...:false"
COMFY_ENV_NAME=comfy_env
COMFY_REPO_URL=https://github.com/comfyanonymous/ComfyUI.git
COMFY_DATA_DIR=/data/marketing
COMFY_DIR=/data/marketing/comfy
COMFY_EXTENSION_LIST=comfy_data/extension_list.txt
COMFY_EXTRA_MODEL_PATHS=comfy_data/extra_model_paths.yaml
```

`ADMIN_USERS` allows defining multiple users at once using a semicolon separated
list with the format `username:ssh_key:sudo`. Set `sudo` to `true` to grant the
user passwordless sudo access.

The `setup_comfy_env.sh` script installs ComfyUI into `/data/marketing/comfy`,
installs PyTorch from the official wheel index, clones any extensions listed in
`comfy_data/extension_list.txt`, and copies `comfy_data/extra_model_paths.yaml`
to the ComfyUI directory.

### S3 Mount Requirements

The `mount_s3.sh` script uses `s3fs` which relies on the FUSE kernel module. Ensure
your container has access to `/dev/fuse` and that FUSE is enabled on the host.
When running with Docker, start the container with `--device /dev/fuse --cap-add SYS_ADMIN`
(or `--privileged`) so the script can successfully mount the bucket.

If FUSE cannot be enabled, the script falls back to copying the bucket with
`aws s3 sync`. This provides a one-time synchronization but does not create a
live mount.

