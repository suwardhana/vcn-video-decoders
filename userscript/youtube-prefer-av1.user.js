// ==UserScript==
// @name         YouTube: prefer AV1 over VP9
// @description  Reports VP9 as not smooth / not power-efficient in Media Capabilities, the way Safari does on Macs without VP9 hardware, so YouTube picks AV1 (hardware-decoded through the AMD VCN VideoToolbox plugin) when a video has it. VP9 stays supported, so videos without AV1 still play VP9 up to 4K.
// @version      2.0
// @match        https://www.youtube.com/*
// @match        https://m.youtube.com/*
// @match        https://www.youtube-nocookie.com/*
// @run-at       document-start
// @inject-into  page
// @grant        none
// ==/UserScript==
// Do NOT hide VP9 from MediaSource.isTypeSupported: YouTube sends that answer to the server as
// devicePlaybackCapabilities.supportsVp9Encoding, and with false the server drops AV1 too (H.264 only).
(() => {
  "use strict";
  const isVP9 = (s) => /vp0?9/i.test(String(s || ""));
  const mc = navigator.mediaCapabilities;
  if (!mc || !mc.decodingInfo) return;
  const orig = mc.decodingInfo.bind(mc);
  mc.decodingInfo = async (cfg) => {
    const r = await orig(cfg);
    if (cfg && cfg.video && isVP9(cfg.video.contentType) && r && r.supported) {
      return { supported: true, smooth: false, powerEfficient: false, configuration: r.configuration };
    }
    return r;
  };
  console.debug("[prefer-av1] VP9 reported as not power-efficient");
})();
