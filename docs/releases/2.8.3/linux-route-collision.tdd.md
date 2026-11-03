# Linux route-collision TDD evidence

## Source and journey

This task was derived from a live Ubuntu 26.10 failure: WProxy and a Docker bridge both owned `172.19.0.1`. As a Linux user, connecting WProxy must select a TUN subnet that does not overlap an existing route, and Manager and GNOME Quick Settings must use the same scoped administrator helper.

## RED and GREEN

| Guarantee | Test | RED evidence | GREEN evidence |
| --- | --- | --- | --- |
| An overlapping Docker route rejects `172.19.0.0/30` and selects the next private `/30` | `RunnerTests.test_tun_ipv4_selection_skips_an_overlapping_docker_route` | Missing selector function | Selected `172.31.255.1/30` |
| sing-box receives the runtime-selected Linux address | `EnginesTests.test_sing_box_uses_the_runtime_selected_linux_tun_address` | Config retained `172.19.0.1/30` | Config used `WPROXY_TUN_IPV4` |
| GNOME connect/disconnect uses the same fixed Polkit helper as Manager | `ReleaseTests.test_gnome_connect_and_disconnect_use_the_same_admin_helper_as_manager` | Extension invoked `wproxyctl nm` directly | Extension invokes `/usr/libexec/wproxy-admin` through `pkexec` |

RED command and result: `python3 -m unittest tests/test_runtime.py tests/test_engines.py tests/test_release.py -v` — 46 passed, 3 intended failures.

GREEN command and result: the same command — 49 passed.

## Target acceptance

On Ubuntu 26.10 with an existing Docker `172.19.0.0/16` bridge, installed WProxy activated on `172.31.255.1/30`; HTTPS through `wproxy0` returned 204. A temporary `/usr/bin/curl` split-routing entry produced a different public egress address than the physical interface without printing either address. The temporary entry was removed and the final policy contains only `/usr/lib/chatgpt/ChatGPT`.

## Coverage and gaps

The focused tests cover the selector decision, engine handoff and GNOME authorization path. Fedora SELinux acceptance and Windows installer acceptance remain separate target checks performed by their own environments; local Ubuntu acceptance does not establish those results.
