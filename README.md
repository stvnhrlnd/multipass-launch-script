# Multipass Launch Script

This is a Bash script I use to spin up and configure [Multipass](https://multipass.run/) instances for research and development purposes.

By default Multipass instances only have 1GB of RAM, 5GB of disk, and 1 CPU, which is not enough for me, so I've hardcoded some better defaults (8GB of RAM, 20GB of disk, and 4 CPUs). This can be overridden at the command line.

The script adds your SSH public key to the instance's `~/.ssh/authorized_keys` file and updates `~/.ssh/config` on the host so you can connect to it over SSH. This way it's possible to use the [Visual Studio Code Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) extension for development work within the instance.

It also updates the maximum number of files that can be watched in the instance. I was running into errors when opening large repositories in VS Code (looking at you, Umbraco 🧐), and this appeared to be the solution. See ["Visual Studio Code is unable to watch for file changes in this large workspace" (error ENOSPC)](https://code.visualstudio.com/docs/setup/linux#_visual-studio-code-is-unable-to-watch-for-file-changes-in-this-large-workspace-error-enospc).

## Usage

Download the script, make it executable, and run:

```bash
wget https://raw.githubusercontent.com/stvnhrlnd/multipass-launch-script/main/mpl.sh
chmod u+x mpl.sh
./mpl.sh -h
```

I also have the script on my `PATH` so I can run it from anywhere without typing the full path at the command line.

Any options after a `--` by itself will be passed through to the `multipass launch` command under the hood, in case you want to specify a name for the VM, different specs, or a different image:

```bash
./mpl.sh --ssh-key ~/.ssh/id_rsa.pub -- --name bobby --cpus 2 --disk 10G --memory 4G jammy
```

See the [`multipass launch`](https://multipass.run/docs/launch-command) docs for all available options.

## Screenshot

![Multipass Launch Script executed in a terminal window.](/screenshot.png)

## Disclaimer

It works on my machine.
