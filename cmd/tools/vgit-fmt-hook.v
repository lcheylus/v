import os
import crypto.sha256

// Tempd for debug
import time

const vexe = os.getenv_opt('VEXE') or { panic('missing VEXE env variable') }
const vroot = os.to_slash(os.real_path(os.dir(vexe)))
const horiginal = os.to_slash(os.join_path(vroot, 'cmd/tools/git_pre_commit_hook.vsh'))
const hbtarget = os.to_slash(os.join_path(os.vtmp_dir(), 'git_pre_commit_hook'))

fn get_hook_target(git_folder string) string {
	return os.to_slash(os.join_path(git_folder, 'hooks/pre-commit'))
}

// Build binary for Git hook from cmd/tools/git_pre_commit_hook.vsh script
fn build_btarget() {
	if os.exists(horiginal) && os.is_file(horiginal) {
		res := os.execute('${vexe} -skip-running -o ${hbtarget} ${horiginal}')
		if res.exit_code != 0 {
			println('Error when building ${hbtarget} - error = ${res.output}')
			exit(1)
		} else {
			println('Build ${hbtarget} done')
			// DEBUG 'ls -l file'
			$if windows {
				stat := os.stat('${hbtarget}.exe') or {
					eprintln('Error: ${err}')
					return
				}

				// File type
				file_type := if os.is_dir(hbtarget) {
					'd'
				} else {
					'-'
				}
				// Permissions (Unix-style)
				perms := stat.get_mode().bitmask()
				// Size
				size := stat.size
				// Modified time
				mtime := time.unix(stat.mtime)
				mtime_str := mtime.format_ss()

				println('${file_type}${perms} ${size} ${mtime_str} ${hbtarget}.exe')
			}
		}
	} else {
		println('Unable to find ${horiginal} file')
		exit(1)
	}
}

fn main() {
	git_folder := find_nearest_top_level_folder_with_a_git_subfolder(os.getwd()) or {
		eprintln('This command has to be run inside a Git repository.')
		exit(0)
	}
	os.chdir(git_folder)!
	htarget := get_hook_target(git_folder)
	cmd := os.args[2] or { 'status' }
	match cmd {
		'status' {
			cmd_status(htarget)
		}
		'install' {
			cmd_install(htarget)
		}
		'remove' {
			cmd_remove(htarget)
		}
		else {
			eprintln('Unknown command `${cmd}`. Known commands are: `status`, `install` or `remove`')
			exit(1)
		}
	}
}

fn cmd_status(htarget string) {
	report_status(htarget, true)
}

fn cmd_install(htarget string) {
	if report_status(htarget, false) {
		return
	}
	println('> Installing the newest version of ${horiginal} over ${htarget} ...')
	$if windows {
		os.cp('${hbtarget}.exe', htarget) or { err_exit('failed to copy to ${htarget}') }
	} $else {
		os.cp(hbtarget, htarget) or { err_exit('failed to copy to ${htarget}') }
	}
	println('> Done.')
}

fn cmd_remove(htarget string) {
	report_status(htarget, false)
	if !os.exists(htarget) {
		err_exit('file ${htarget} has been removed already')
	}
	println('> Removing ${htarget} ...')
	os.rm(htarget) or { err_exit('failed to remove ${htarget}') }
	println('> Done.')
}

// Returns true if binary compiled from cmd/tools/git_pre_commit_hook.vsh and
// pre-commit Git hook are identical.
fn report_status(htarget string, show_instructions bool) bool {
	mut hbftarget := ''
	$if windows {
		hbftarget = hbtarget + '.exe'
	} $else {
		hbftarget = hbtarget
	}
	if !os.exists(hbftarget) || !os.is_executable(hbftarget) {
		build_btarget()
	}

	ostat := os.stat(horiginal) or { os.Stat{} }
	// bstat := os.stat(hbtarget) or { os.Stat{} }
	bstat := os.stat(hbftarget) or { os.Stat{} }
	tstat := os.stat(htarget) or { os.Stat{} }
	// bhash := hash_file(hbtarget) or { '' }
	bhash := hash_file(hbftarget) or { '' }
	thash := hash_file(htarget) or { '' }
	if os.exists(htarget) && os.is_file(htarget) {
		println('>   CURRENT git repo pre-commit hook: size: ${tstat.size:6} bytes, sha256: ${thash}, ${htarget}')
	} else {
		println('>   CURRENT git repo pre-commit hook: missing ${htarget}')
	}
	// TODO: add error
	if os.exists(horiginal) && os.is_file(horiginal) {
		println('> Main V repo pre-commit hook script: size: ${ostat.size:6} bytes, ${horiginal}')
	}
	// if os.exists(hbtarget) && os.is_file(hbtarget) {
	// if !os.exists(hbtarget) {
	if !os.exists(hbftarget) {
		println('Error no ${hbftarget} file')
		return false
		// } else if !os.is_executable(hbtarget) {
	} else if !os.is_executable(hbftarget) {
		println('Error ${hbftarget} not executable')
		return false
	} else {
		println('> Main V repo pre-commit hook binary: size: ${bstat.size:6} bytes, sha256: ${bhash}, ${hbtarget}')
	}
	if bhash == thash {
		println('> Both files are exactly the same.')
		if show_instructions {
			show_msg_about_removing(htarget)
		}
		return true
	}
	println('> Files have different hashes.')
	if bhash != '' && thash != '' {
		existing_content := os.read_file(htarget) or { '' }
		if !existing_content.contains('hooks.stopCommitOfNonVfmtedVFiles') {
			// both files do exist, but the current git repo hook, is not compatible (an older version of git_pre_commit_hook.vsh):
			err_exit('the existing file ${htarget} , does not appear to be a compatible V formatting hook\nYou have to remove it manually')
		}
	}
	if show_instructions {
		println("> Use `v git-fmt-hook install` to update the CURRENT repository's pre-commit hook,")
		println('> with the newest pre-commit formatting script from the main V repo.')
		show_msg_about_removing(htarget)
	}
	return false
}

fn show_msg_about_removing(htarget string) {
	if os.exists(htarget) {
		println("> Use `v git-fmt-hook remove` to remove the CURRENT repository's pre-commit hook.")
	}
}

fn find_nearest_top_level_folder_with_a_git_subfolder(current string) ?string {
	mut cfolder := os.to_slash(os.real_path(current))
	for level := 0; level < 255; level++ {
		if cfolder == '/' || cfolder == '' {
			break
		}
		git_folder := os.join_path(cfolder, '.git')
		if os.is_dir(git_folder) {
			return git_folder
		}
		cfolder = os.dir(cfolder)
	}
	return none
}

fn hash_file(path string) !string {
	fbytes := os.read_bytes(path)!
	mut digest256 := sha256.new()
	digest256.write(fbytes)!
	mut sum256 := digest256.sum([])
	return sum256.hex()
}

@[no_return]
fn err_exit(msg string) {
	eprintln('> error: ${msg} .')
	exit(0) // note: this is important, since the command is ran in `v up` and during `make`
}
