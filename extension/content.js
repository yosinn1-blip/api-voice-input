// API音声ソフトが録音を始めたら、このタブで再生中の動画を止める。
//
// なぜページ側で受けるのか（2026-09-18）:
// アプリ（macOS 側）からは「どのタブが鳴っているか」を知る手段がない。
// 全タブへ AppleScript で JavaScript を撃つと、Chrome が破棄済みタブを1枚ずつ
// 復帰させるため実測で842秒かかった。アクティブタブだけに絞ると背面タブを取りこぼす。
// content script は「生きているタブ」だけで動く＝鳴っているタブは必ず含まれ、
// 破棄済みタブを起こすこともない。
//
// service worker ではなく content script に置いているのは、MV3 の service worker が
// 30秒のアイドルで終了してしまい、合図を受け取れなくなるため。
(() => {
  // content_scripts による注入と、拡張更新時の executeScript による注入が
  // 同じタブで重なることがある。EventSource を二重に張らない。
  if (window.__apiVoiceInputPauseInstalled) return;
  window.__apiVoiceInputPauseInstalled = true;

  const ENDPOINT = "http://127.0.0.1:47623";
  const INITIAL_RETRY_MS = 3000;
  const MAX_RETRY_MS = 60000;

  let source = null;
  let retryMs = INITIAL_RETRY_MS;
  let retryTimer = null;

  function pauseVideos() {
    let paused = 0;
    for (const video of document.querySelectorAll("video")) {
      if (!video.paused) {
        video.pause();
        paused += 1;
      }
    }
    // 何本止めたかをアプリ側のログに残す。効いているかを後から確かめるため。
    // POST ではなく GET なのは、Chrome が POST の fetch をローカルアドレス宛に
    // 送らずハングする場面を実機で踏んだため（EventSource と同じ GET なら通る）。
    fetch(`${ENDPOINT}/paused?n=${paused}`, { method: "GET", keepalive: true }).catch(() => {});
  }

  function scheduleReconnect() {
    if (retryTimer !== null) return;
    // アプリが起動していないときに繋ぎ続けないよう、間隔を伸ばしていく。
    retryTimer = setTimeout(() => {
      retryTimer = null;
      connect();
    }, retryMs);
    retryMs = Math.min(retryMs * 2, MAX_RETRY_MS);
  }

  function connect() {
    if (source) {
      source.close();
      source = null;
    }
    source = new EventSource(`${ENDPOINT}/events`);
    source.onopen = () => {
      retryMs = INITIAL_RETRY_MS;
    };
    source.onmessage = (event) => {
      if (event.data === "pause") pauseVideos();
    };
    source.onerror = () => {
      if (source) {
        source.close();
        source = null;
      }
      scheduleReconnect();
    };
  }

  // タブが裏に回っている間も接続は保つ（裏で鳴っている動画こそ止めたい相手なので）。
  connect();
})();
