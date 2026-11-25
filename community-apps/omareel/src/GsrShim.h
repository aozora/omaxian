#pragma once

// Omaxian: `omareel __record-gsr` when gpu-screen-recorder is not on PATH.
//
// Omaxian runs gpu-screen-recorder from Flatpak through `omarchy-gpu-screen-recorder`. The
// recorder daemon stops its child with SIGINT (and SIGTERM when that takes too long), but under
// Flatpak the child is bwrap: it dies on the signal and leaves the sandboxed gpu-screen-recorder
// running, so the file is never finalised. This forks the wrapper, passes SIGINT, SIGTERM and
// SIGHUP on to the gpu-screen-recorder processes among its descendants (to the wrapper itself
// while there are none yet), and exits as the wrapper does.

#include <csignal>
#include <cstdio>
#include <cstring>
#include <dirent.h>
#include <fstream>
#include <map>
#include <string>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

namespace omaxian {

// Every process's parent, from /proc/<pid>/stat, and its command name.
inline void readProcesses(std::multimap<pid_t, pid_t> &children, std::map<pid_t, std::string> &names)
{
    DIR *proc = ::opendir("/proc");
    if (!proc) return;
    while (dirent *entry = ::readdir(proc)) {
        char *end = nullptr;
        const long pid = std::strtol(entry->d_name, &end, 10);
        if (pid <= 0 || *end) continue;
        std::ifstream file("/proc/" + std::string(entry->d_name) + "/stat");
        std::string stat;
        if (!std::getline(file, stat)) continue;
        // pid (comm) state ppid ...; comm may hold spaces and parentheses, so take the last ')'.
        const size_t open = stat.find('('), close = stat.rfind(')');
        if (open == std::string::npos || close == std::string::npos || close < open) continue;
        char state = 0;
        long ppid = 0;
        if (std::sscanf(stat.c_str() + close + 1, " %c %ld", &state, &ppid) != 2) continue;
        children.emplace(pid_t(ppid), pid_t(pid));
        names[pid_t(pid)] = stat.substr(open + 1, close - open - 1);
    }
    ::closedir(proc);
}

// The gpu-screen-recorder processes descending from `root` (the kernel cuts the command name to
// 15 characters: "gpu-screen-reco").
inline std::vector<pid_t> recorderDescendants(pid_t root)
{
    std::multimap<pid_t, pid_t> children;
    std::map<pid_t, std::string> names;
    readProcesses(children, names);
    std::vector<pid_t> found, pending{root};
    while (!pending.empty()) {
        const pid_t parent = pending.back();
        pending.pop_back();
        const auto range = children.equal_range(parent);
        for (auto it = range.first; it != range.second; ++it) {
            if (names[it->second].rfind("gpu-screen-reco", 0) == 0) found.push_back(it->second);
            pending.push_back(it->second);
        }
    }
    return found;
}

inline int runFlatpakGsr(std::vector<char *> arguments)
{
    sigset_t forwarded;
    sigemptyset(&forwarded);
    for (const int signal : {SIGINT, SIGTERM, SIGHUP, SIGCHLD}) sigaddset(&forwarded, signal);
    sigset_t previous;
    ::sigprocmask(SIG_BLOCK, &forwarded, &previous);
    const pid_t child = ::fork();
    if (child < 0) {
        std::fprintf(stderr, "omareel: could not start omarchy-gpu-screen-recorder: %s\n", std::strerror(errno));
        return 127;
    }
    if (child == 0) {
        ::sigprocmask(SIG_SETMASK, &previous, nullptr);
        arguments[0] = const_cast<char *>("omarchy-gpu-screen-recorder");
        ::execvp("omarchy-gpu-screen-recorder", arguments.data());
        std::fprintf(stderr, "omareel: could not exec gpu-screen-recorder or omarchy-gpu-screen-recorder: %s\n",
                     std::strerror(errno));
        ::_exit(127);
    }
    const timespec tick{0, 200 * 1000 * 1000};
    for (;;) {
        const int signal = ::sigtimedwait(&forwarded, nullptr, &tick);
        if (signal == SIGINT || signal == SIGTERM || signal == SIGHUP) {
            const std::vector<pid_t> recorders = recorderDescendants(child);
            if (recorders.empty()) ::kill(child, signal);
            for (const pid_t recorder : recorders) ::kill(recorder, signal);
        }
        int status = 0;
        const pid_t done = ::waitpid(child, &status, WNOHANG);
        if (done == child) {
            if (WIFEXITED(status)) return WEXITSTATUS(status);
            if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
            return 1;
        }
        if (done < 0 && errno != EINTR) return 1;
    }
}

} // namespace omaxian
