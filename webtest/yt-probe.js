// Paste into Safari's Web Inspector console on a youtube.com/watch page.
// Shows how this browser answers the codec questions YouTube's player asks, plus YouTube's AV1 flags.
(async () => {
  const out = [];
  const T = (s) => { try { return MediaSource.isTypeSupported(s); } catch (e) { return "ERR " + e; } };
  const types = [
    'video/mp4; codecs="av01.0.05M.08"',
    'video/mp4; codecs="av01.0.12M.08"; width=3840; height=2160; framerate=60',
    'video/mp4; codecs="av01.0.13M.08"; width=3840; height=2160; framerate=60; bitrate=20000000',
    'video/mp4; codecs="av01.0.16M.08"; width=7680; height=4320; framerate=60',
    'video/mp4; codecs="av01.0.13M.10.0.110.09.16.09.0"',
    'video/mp4; codecs="av01.0.13M.10"; eotf=smpte2084',
    'video/webm; codecs="vp9"; width=3840; height=2160; framerate=60',
    'video/webm; codecs="vp09.02.51.10.01.09.16.09.00"',
  ];
  for (const t of types) out.push(["MSE", t, T(t)]);
  out.push(["canPlayType av01", "", document.createElement("video").canPlayType('video/mp4; codecs="av01.0.05M.08"')]);
  const flags = (window.yt && yt.config_ && yt.config_.EXPERIMENT_FLAGS) || (window.ytcfg && ytcfg.get && ytcfg.get("EXPERIMENT_FLAGS")) || {};
  for (const [k, v] of Object.entries(flags)) if (/av1|av01|dav1d/i.test(k)) out.push(["flag", k, String(v)]);
  try {
    const pr = window.ytInitialPlayerResponse || (document.querySelector("#movie_player") && document.querySelector("#movie_player").getPlayerResponse && document.querySelector("#movie_player").getPlayerResponse());
    const fmts = (pr && pr.streamingData && pr.streamingData.adaptiveFormats) || [];
    const av1 = fmts.filter((f) => /av01/.test(f.mimeType)).map((f) => f.qualityLabel);
    const vp9 = fmts.filter((f) => /vp09|vp9/.test(f.mimeType)).map((f) => f.qualityLabel);
    out.push(["formats in player response", "AV1: " + (av1.join(",") || "none"), "VP9: " + (vp9.join(",") || "none")]);
  } catch (e) { out.push(["formats", "", "ERR " + e]); }
  try { out.push(["localStorage yt-player-av1-pref", "", localStorage.getItem("yt-player-av1-pref")]); } catch (e) {}
  out.push(["cookie PREF", "", (document.cookie.match(/PREF=[^;]*/) || ["none"])[0]]);
  console.table(out);
  return out.map((r) => r.join(" | ")).join("\n");
})();
