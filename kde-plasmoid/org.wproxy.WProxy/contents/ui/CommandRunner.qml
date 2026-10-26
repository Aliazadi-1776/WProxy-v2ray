import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/Commands.js" as Commands

Plasma5Support.DataSource {
    id: runner
    engine: "executable"
    connectedSources: []
    interval: 0

    property var jobs: ({})
    property int activeJobs: 0
    signal completed(string token, int exitCode, string output, string error)

    function run(token, args) {
        const source = Commands.command(args);
        if (jobs[source])
            return false;
        const next = Object.assign({}, jobs);
        next[source] = {token: token, started: Date.now()};
        jobs = next;
        activeJobs += 1;
        connectSource(source);
        return true;
    }

    function take(source) {
        if (!jobs[source])
            return null;
        const next = Object.assign({}, jobs);
        const job = next[source];
        delete next[source];
        jobs = next;
        activeJobs = Math.max(0, activeJobs - 1);
        disconnectSource(source);
        return job;
    }

    onNewData: function(sourceName, data) {
        if (!jobs[sourceName] || data["exit code"] === undefined)
            return;
        const job = take(sourceName);
        completed(job.token, Number(data["exit code"]), String(data.stdout || ""), String(data.stderr || ""));
    }

    property Timer watchdog: Timer {
        interval: 3000
        running: runner.activeJobs > 0
        repeat: true
        onTriggered: {
            const sources = Object.keys(runner.jobs);
            for (let index = 0; index < sources.length; index += 1) {
                const source = sources[index];
                const job = runner.jobs[source];
                if (Date.now() - job.started < 120000)
                    continue;
                const timedOut = runner.take(source);
                runner.completed(timedOut.token, 124, "", "Command timed out. Check WProxy and the Plasma5Support executable engine.");
            }
        }
    }

    Component.onDestruction: {
        for (const source in jobs)
            disconnectSource(source);
        jobs = {};
        activeJobs = 0;
    }
}
