#!/bin/bash

# ---------------------------------------------------------------------------- #
#                                 Shell Options                                #
# ---------------------------------------------------------------------------- #

# This section of code was lifted from this project:
#   https://github.com/ralish/bash-script-template

# For an explanation of the options see this article:
#   https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
  set -o xtrace # Trace the execution of the script (debug)
fi

# Only enable these shell behaviours if we're not being sourced
# Approach via: https://stackoverflow.com/a/28776166/8787985
if ! (return 0 2>/dev/null); then
  # A better class of script...
  set -o errexit  # Exit on most errors (see the manual)
  set -o nounset  # Disallow expansion of unset variables
  set -o pipefail # Use last non-zero exit code in a pipeline
fi

# Enable errtrace or the error trap handler will not work as expected
set -o errtrace # Ensure the error trap handler is inherited

# ---------------------------------------------------------------------------- #
#                                   Functions                                  #
# ---------------------------------------------------------------------------- #

# DESC: Show the script help message
function mpl_usage() {
  cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [--ssh-key FILE] [-- LAUNCH_OPTIONS]

Launch a Multipass instance with sensible defaults and configure it for SSH
connections from the host. Any options after a \`--\` by itself will be passed
through to the \`multipass launch\` command under the hood. See the Multipass
docs for available launch options: https://multipass.run/docs/launch-command

Options:
  -h, --help      Show this help message
  --ssh-key FILE  SSH public key file (default: ~/.ssh/id_rsa.pub)
EOF
}

# DESC: Print a message to stdout with a new line
# ARGS: $1 (required): Message to print
function mpl_print() {
  local -r message="$1"
  printf '%s\n' "${message}"
}

# DESC: Print an informational message
# ARGS: $1 (required): Message to print
function mpl_print_info() {
  local -r message="$1"
  mpl_print "[*] ${message}"
}

# DESC: Print an error message to stderr
# ARGS: $1 (required): Message to print
function mpl_print_error() {
  local -r message="$1"
  mpl_print "[!] ${message}" >&2
}

# DESC: Handler for unexpected errors
function mpl_trap_err() {
  # Disable the error trap handler to prevent potential recursion
  trap - ERR

  # Consider any further errors non-fatal to ensure we run to completion
  set +o errexit
  set +o pipefail

  # Exit with failure status
  exit 1
}

# DESC: Check if a command exists on the system
# ARGS: $1 (required): Command to check
function mpl_is_command() {
  local -r command="$1"
  command -v "${command}" >/dev/null 2>&1
}

# DESC: Ensure that the given SSH public key file exists and is valid
# ARGS: $1 (required): Path to the SSH public key file
function mpl_validate_ssh_key() {
  local -r ssh_key_file="$1"
  ssh-keygen -l -f "${ssh_key_file}" >/dev/null
}

# DESC: Launch a Multipass instance and output the instance name
# ARGS: $@ (optional): Options to be passed to `multipass launch` command
function mpl_launch_instance() {
  local -r cpus=4
  local -r disk='20G'
  local -r memory='8G'

  # NOTE: When given duplicate options, Multipass will choose the last one as it
  #       appears on the command line. So the defaults here will be overridden by the
  #       args provided to the function.
  multipass launch --cpus "${cpus}" --disk "${disk}" --memory "${memory}" "$@" |
    grep 'Launched:' | cut -d ' ' -f 2
}

# DESC: Add an SSH key to the `~/.ssh/authorized_keys` file in a Multipass instance
# ARGS: $1 (required): Path to the SSH public key file
#       $2 (required): Name of the Multipass instance
function mpl_add_ssh_key() {
  local -r ssh_key_file="$1"
  local -r instance_name="$2"

  # Read in SSH key and strip any single quotes to prevent command injection
  local -r ssh_key=$(tr -d "'" <"${ssh_key_file}")

  mpl_print_info 'Adding SSH key...'
  multipass exec "${instance_name}" -- bash -c "echo '${ssh_key}' >> ~/.ssh/authorized_keys"
}

# DESC: Increase maximum number of files that can be watched in a Multipass instance
# ARGS: $1 (required): Name of the Multipass instance
function mpl_set_max_user_watches() {
  local -r instance_name="$1"

  # https://code.visualstudio.com/docs/setup/linux#_visual-studio-code-is-unable-to-watch-for-file-changes-in-this-large-workspace-error-enospc
  mpl_print_info 'Increasing maximum number of file watchers...'
  multipass exec "${instance_name}" -- \
    bash -c "echo 'fs.inotify.max_user_watches=524288' | sudo tee -a /etc/sysctl.conf >/dev/null; sudo sysctl -p >/dev/null"
}

# DESC: Add an entry to the current user's SSH config file for a Multipass instance
# ARGS: $1 (required): Name of the Multipass instance
function mpl_update_ssh_config() {
  local -r instance_name="$1"

  local -r instance_ip=$(
    multipass info --format json "${instance_name}" |
      jq --arg instance_name "${instance_name}" '.info[$instance_name].ipv4[0]'
  )

  local -r ssh_config_file="${HOME}/.ssh/config"
  local -r ssh_config=$(cat "${ssh_config_file}")

  mpl_print_info 'Updating SSH config...'

  # Prepend new host to existing config so that it takes precedence over any existing
  # hosts with the same name.
  printf 'Host %s\n  HostName %s\n  User ubuntu\n\n%s' \
    "${instance_name}" "${instance_ip}" "${ssh_config}" >"${ssh_config_file}"
}

# DESC: Main entry point
# ARGS: $@ (optional): See usage for available arguments
function mpl() {
  local ssh_key_file="${HOME}/.ssh/id_rsa.pub"

  # Parse arguments
  local param
  while [[ $# -gt 0 ]]; do
    param="$1"
    shift

    case "${param}" in
    -h | --help)
      mpl_usage
      return 0
      ;;
    --ssh-key)
      ssh_key_file="$1"
      readonly ssh_key_file
      shift
      ;;
    --)
      # Anything that follows a `--` by itself is passed through to Multipass
      break
      ;;
    *)
      mpl_print_error "Invalid parameter: ${param}"
      return 2
      ;;
    esac
  done

  # The remaining arguments are Multipass launch options
  local -r launch_options=("$@")

  # Do all the things!
  mpl_print 'Multipass Launch Script v0.1.0'
  mpl_print '=================================================='

  if ! mpl_is_command multipass; then
    mpl_print_error 'Multipass is not installed.'
    return 1
  fi

  mpl_print_info "Using SSH key: ${ssh_key_file}"
  if ! mpl_validate_ssh_key "${ssh_key_file}"; then
    mpl_print_error 'A valid SSH key is required. Run ssh-keygen to generate an SSH key and try again.'
    return 1
  fi

  mpl_print_info 'Launching Multipass instance...'
  local -r instance_name=$(mpl_launch_instance "${launch_options[@]}")
  if [[ -z "${instance_name}" ]]; then
    mpl_print_error 'An error occurred when launching the instance.'
    return 1
  fi

  mpl_print_info 'Instance launched:'
  multipass info "${instance_name}"

  mpl_set_max_user_watches "${instance_name}"
  mpl_add_ssh_key "${ssh_key_file}" "${instance_name}"
  mpl_update_ssh_config "${instance_name}"

  mpl_print_info "Instance ready. Connect with: ssh ${instance_name}"
}

# ---------------------------------------------------------------------------- #
#                                  Let's go!!                                  #
# ---------------------------------------------------------------------------- #

# Invoke mpl with args if not sourced
if ! (return 0 2>/dev/null); then
  trap mpl_trap_err ERR
  mpl "$@"
fi
