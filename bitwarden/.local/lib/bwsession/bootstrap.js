// bwsession CLI bootstrap: node bootstrap.js CLI_JS TOKEN_FD [bw arguments...]
//
// The session token arrives on an inherited pipe and is set in process.env
// here, after exec.  It is therefore never part of this process's exec-time
// environment block, which is what /proc/PID/environ and systemd-coredump's
// COREDUMP_ENVIRON journal field are read from.  The Bitwarden CLI reads
// process.env.BW_SESSION lazily (NodeEnvSecureStorageService.getSessionKey),
// so the token is in place before it is needed.  RLIMIT_CORE=0, inherited
// from the Python caller, keeps systemd-coredump from storing a core image.
"use strict";

const fs = require("fs");
const path = require("path");

const TOKEN = /^[A-Za-z0-9+/=_-]{16,512}$/;

function fail() {
    process.stderr.write("bw-session: bootstrap failed\n");
    process.exit(70);
}

// Node diagnostic reports include process.env; keep them off whatever the flags.
if (process.report) {
    try {
        process.report.reportOnFatalError = false;
        process.report.reportOnSignal = false;
        process.report.reportOnUncaughtException = false;
    } catch (e) {
        fail();
    }
}

const cli = process.argv[2];
const fdArg = process.argv[3] || "";
if (!cli || !path.isAbsolute(cli) || !/^[0-9]{1,4}$/.test(fdArg)) {
    fail();
}
const fd = Number(fdArg);
if (fd < 3) {
    fail();
}

// Only ever read and close the pipe we were handed, never one of node's own fds.
let isPipe = false;
try {
    isPipe = fs.fstatSync(fd).isFIFO();
} catch (e) {
    isPipe = false;
}
if (!isPipe) {
    fail();
}
let token = null;
try {
    token = fs.readFileSync(fd, { encoding: "ascii" }).replace(/\n$/, "");
} catch (e) {
    token = null;
}
try {
    fs.closeSync(fd);
} catch (e) {
    // already closed
}
if (token === null || !TOKEN.test(token)) {
    fail();
}

process.env.BW_SESSION = token;
token = null;
process.argv.splice(1, 3, cli);
require(cli);
