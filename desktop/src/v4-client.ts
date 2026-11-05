/** Frontend adapter for the existing Tauri commands. No networking implementation lives here. */
export interface CliOutput { stdout: string; stderr: string; code: number }
export type Invoke = <T>(command: string, args?: Record<string, unknown>) => Promise<T>;
export interface NodeRecord { id: string; name: string; source: string | null; source_name: string; engine?: string; protocol?: string }
export interface TunnelStatus { active: boolean; verified?: boolean; node_id: string | null; name?: string | null; engine?: string; protocol?: string; rx_bytes?: number; tx_bytes?: number; connected_seconds?: number; core_memory_bytes?: number }
export interface Preferences { auto_update: boolean; remember_authorization: boolean }
export interface Routing { mode: 'all' | 'only' | 'bypass'; domains: string[]; apps: string[] }
export interface Subscription { id: string; name: string; node_count: number; updated_at: number | null; usage?: { upload?: number; download?: number; total?: number; expire?: number } }
export interface Core { engine: string; available: boolean; version: string | null }
export interface Snapshot { platform: string; nodes: NodeRecord[]; subscriptions: Subscription[]; status: TunnelStatus; routing: Routing; preferences: Preferences; cores: Core[] }
export interface Ping { id: string; latency_ms: number | null }

export function createDesktopClient(invoke: Invoke, native: boolean) {
  function requireNative() {
    if (!native) throw new Error('Design preview: use the installed WProxy app for this action.');
  }
  async function call<T>(command: string, args?: Record<string, unknown>): Promise<T> {
    requireNative();
    const result = await invoke<T>(command, args);
    if (result && typeof result === 'object' && 'code' in result && Number(result.code) !== 0) {
      const output = result as unknown as CliOutput;
      throw new Error(output.stderr.trim() || `WProxy command failed (${output.code}).`);
    }
    return result;
  }
  function parse<T>(output: CliOutput): T {
    try { return JSON.parse(output.stdout) as T; }
    catch { throw new Error('WProxy returned an unreadable response. Refresh and try again.'); }
  }
  async function ctl<T>(args: string[]): Promise<T> { return parse<T>(await call<CliOutput>('run_ctl', { args })); }
  async function status(): Promise<TunnelStatus> { return parse<TunnelStatus>(await call<CliOutput>('tunnel_status')); }
  async function read(): Promise<Snapshot> {
    const [platform, nodes, subscriptions, current, routing, preferences, cores] = await Promise.all([
      call<string>('platform'), ctl<NodeRecord[]>(['node','list','--json']),
      ctl<Subscription[]>(['sub','list','--json']), status(),
      ctl<Routing>(['routing','show','--json']), ctl<Preferences>(['settings','show','--json']),
      ctl<Core[]>(['core','list','--json']),
    ]);
    return { platform, nodes, subscriptions, status: current, routing, preferences, cores };
  }
  async function connect(nodeId: string, snapshot: Snapshot) {
    if (snapshot.routing.mode === 'only' && !snapshot.routing.apps.length && !snapshot.routing.domains.length) {
      throw new Error('Only selected has no apps or sites. Add an item or choose All traffic.');
    }
    if (!snapshot.nodes.some(node => node.id === nodeId)) throw new Error('This server is no longer in your library. Refresh and try again.');
    if (snapshot.status.active && snapshot.status.node_id === nodeId) return;
    await call<CliOutput>('tunnel', { action: 'up', nodeId, remember: snapshot.preferences.remember_authorization });
  }
  async function quickConnect(snapshot: Snapshot) {
    const best = await ctl<{ id: string; verified: boolean; latency_ms: number }>(['node','best','--verify','--json','--timeout','2']);
    if (best.verified !== true || !snapshot.nodes.some(node => node.id === best.id)
      || !Number.isFinite(best.latency_ms) || best.latency_ms < 0) throw new Error('No valid HTTPS-verified server was returned.');
    await connect(best.id, snapshot);
    return best;
  }
  async function route(args: string[], snapshot: Snapshot) {
    await call<CliOutput>('run_ctl', { args: ['routing', ...args] });
    if (snapshot.platform === 'linux') {
      if (snapshot.status.active && snapshot.status.node_id) {
        await call<CliOutput>('tunnel', { action: 'up', nodeId: snapshot.status.node_id, remember: snapshot.preferences.remember_authorization });
      } else await call<CliOutput>('sync_linux');
    }
  }
  async function sync(platform: string) { if (platform === 'linux') await call<CliOutput>('sync_linux'); }
  async function remove(kind: 'node' | 'sub', id: string, snapshot: Snapshot) {
    const current = await status();
    if (current.active && (kind === 'node' ? current.node_id === id : snapshot.nodes.some(node => node.id === current.node_id && node.source === id))) {
      throw new Error('Disconnect this server before removing it or its subscription.');
    }
    await call<CliOutput>('run_ctl', { args: [kind,'remove',id] });
    await sync(snapshot.platform);
  }
  async function addSubscription(url: string, name: string, platform: string) {
    const args = ['sub','add',url]; if (name.trim()) args.push('--name',name.trim());
    const result = await call<CliOutput>('run_ctl', { args });
    const id = result.stdout.trim();
    if (!/^[a-f0-9]{16}$/i.test(id)) throw new Error('The subscription was saved but its ID was unreadable. Refresh before retrying.');
    await call<CliOutput>('run_ctl', { args: ['sub','update',id] });
    await sync(platform);
  }
  return { native, call, ctl, status, read, connect, quickConnect, route, remove, sync, addSubscription,
    disconnect: () => call<CliOutput>('tunnel', { action: 'down', nodeId: null }),
    ping: (id?: string) => ctl<Ping[]>(['node','ping',id || '--all','--json','--timeout','2']),
  };
}
