/*
 * TeeJee.System.vala
 *
 * Copyright 2017 Tony George <teejeetech@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301, USA.
 *
 *
 */

namespace TeeJee.System{

	using TeeJee.ProcessHelper;
	using TeeJee.Logging;
	using TeeJee.Misc;
	using TeeJee.FileSystem;

	// internet helpers ----------------------
	public bool check_internet_connectivity(){

		if (App.skip_connection_check) return true;

		string std_err, std_out;
		string cmd = "aria2c --no-netrc --no-conf --connect-timeout="+App.connect_timeout_seconds.to_string()+" --max-file-not-found=3 --retry-wait=2 --max-tries=3 --dry-run --quiet https://www.google.com/search?q=test";

		int status = exec_sync(cmd, out std_out, out std_err);

		if (std_err.length > 0) log_error(std_err);
		if (status != 0) log_error(_("Internet connection is not active"));

		return (status == 0);
	}

	// open -----------------------------

	public void xdg_open (string file){
		string cmd = "xdg-open '%s'".printf(escape_single_quote(file));
		log_debug(cmd);
		exec_async(cmd);
	}

	// timers --------------------------------------------------

	public GLib.Timer timer_start(){
		var timer = new GLib.Timer();
		timer.start();
		return timer;
	}

	public ulong timer_elapsed(GLib.Timer timer, bool stop = true){
		ulong microseconds;
		double seconds;
		seconds = timer.elapsed (out microseconds);
		if (stop){
			timer.stop();
		}
		return (ulong)((seconds * 1000 ) + (microseconds / 1000));
	}

	public void sleep(int milliseconds){
		Thread.usleep ((ulong) milliseconds * 1000);
	}
}
