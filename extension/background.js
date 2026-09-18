// 拡張を入れた/更新した直後に、すでに開いている YouTube タブへ content script を入れ直す。
//
// Chrome は拡張を読み込んでも既存タブには注入しないため、これが無いと
// ユーザーがタブを1枚ずつリロードする必要がある（実機では139タブあった）。
//
// discarded: false で絞るのが要点。破棄済みタブへ executeScript を撃つとタブが復帰し、
// まさに避けたかった「背面タブを1枚ずつ起こす」コストが戻ってくる。
// 破棄済みタブは音を出していないので、そもそも対象にする必要がない。
const YOUTUBE_URLS = [
  "https://www.youtube.com/*",
  "https://m.youtube.com/*",
  "https://music.youtube.com/*"
];

async function injectIntoLivingYouTubeTabs() {
  const tabs = await chrome.tabs.query({ url: YOUTUBE_URLS, discarded: false });
  let injected = 0;
  for (const tab of tabs) {
    if (tab.id === undefined) continue;
    try {
      await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ["content.js"] });
      injected += 1;
    } catch (error) {
      // 読み込み途中・権限外などは黙って飛ばす（次にそのタブが読み込まれれば自然に入る）
    }
  }
  console.log(`[API音声ソフト] 既存タブへ注入: ${injected} / ${tabs.length}`);
}

chrome.runtime.onInstalled.addListener(injectIntoLivingYouTubeTabs);
chrome.runtime.onStartup.addListener(injectIntoLivingYouTubeTabs);
