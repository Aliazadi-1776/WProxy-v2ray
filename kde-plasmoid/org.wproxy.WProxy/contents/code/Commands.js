// All data from subscriptions remains a single shell argument, including
// quotes, newlines, dollar signs and command substitutions.
function quote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

function command(args) {
    if (!Array.isArray(args) || args.length === 0)
        throw new Error("Missing command");
    return args.map(quote).join(" ");
}

function needsSync(message) {
    return /sync|profile|uuid|unknown connection|not found/i.test(message);
}

function signature(nodes) {
    return JSON.stringify(nodes.map(function(node) { return [node.id, node.name]; }));
}

function latencyText(id, latencies, pinging) {
    if (pinging[id])
        return "…";
    if (!Object.prototype.hasOwnProperty.call(latencies, id))
        return "Ping";
    return latencies[id] === null ? "Timeout" : latencies[id] + " ms";
}
