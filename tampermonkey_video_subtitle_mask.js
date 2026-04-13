// ==UserScript==
// @name         网页视频字幕遮罩 Pro (动态移动+缩放)
// @namespace    http://tampermonkey.net/
// @version      2.0
// @description  为网页视频添加可移动、可调整大小的毛玻璃遮罩。快捷键 Alt+B 开关，Alt+上下调大小，Ctrl+上下调位置。
// @author       Your Personal AI Assistant
// @match        *://*/*
// @grant        none
// ==/UserScript==

(function () {
  "use strict";

  let mask = null;
  let maskHeightPct = 15; // 初始高度 15%
  let maskBottomPct = 0; // 初始位置：贴紧底部 0%

  function toggleMask() {
    if (mask) {
      mask.remove();
      mask = null;
      return;
    }

    const videos = document.querySelectorAll("video");
    if (videos.length === 0) return;

    let targetVideo = videos[0];
    let maxArea = 0;
    videos.forEach((v) => {
      let rect = v.getBoundingClientRect();
      if (rect.width * rect.height > maxArea) {
        maxArea = rect.width * rect.height;
        targetVideo = v;
      }
    });

    const parent = targetVideo.parentElement;
    const parentStyle = window.getComputedStyle(parent);
    if (parentStyle.position === "static") {
      parent.style.position = "relative";
    }

    mask = document.createElement("div");
    mask.style.position = "absolute";
    mask.style.left = "0";
    mask.style.width = "100%";
    mask.style.zIndex = "2147483647";
    mask.style.pointerEvents = "none"; // 鼠标穿透

    // 核心视觉效果
    mask.style.backdropFilter = "blur(15px)";
    mask.style.WebkitBackdropFilter = "blur(15px)";
    mask.style.backgroundColor = "rgba(0, 0, 0, 0.2)";

    // 应用初始尺寸和位置
    updateMaskStyle();
    parent.appendChild(mask);
  }

  // 更新 DOM 样式
  function updateMaskStyle() {
    if (!mask) return;
    mask.style.height = maskHeightPct + "%";
    mask.style.bottom = maskBottomPct + "%";
  }

  // 调整高度 (Alt + 上下)
  function adjustHeight(delta) {
    if (!mask) return;
    maskHeightPct += delta;
    if (maskHeightPct < 1) maskHeightPct = 1;
    // 防止高度超出屏幕剩余空间
    if (maskBottomPct + maskHeightPct > 100)
      maskHeightPct = 100 - maskBottomPct;
    updateMaskStyle();
  }

  // 调整位置 (Ctrl + 上下)
  function adjustPosition(delta) {
    if (!mask) return;
    maskBottomPct += delta;
    if (maskBottomPct < 0) maskBottomPct = 0;
    // 防止遮罩移出画面顶部
    if (maskBottomPct + maskHeightPct > 100)
      maskBottomPct = 100 - maskHeightPct;
    updateMaskStyle();
  }

  // 监听全局快捷键
  window.addEventListener(
    "keydown",
    (e) => {
      // Alt + B : 开关遮罩
      if (
        e.altKey &&
        !e.ctrlKey &&
        !e.shiftKey &&
        e.key.toLowerCase() === "b"
      ) {
        e.preventDefault();
        toggleMask();
      }
      // Alt + 上下 : 调整高度 (改变大小)
      else if (e.altKey && !e.ctrlKey && !e.shiftKey) {
        if (e.key === "ArrowUp") {
          e.preventDefault();
          adjustHeight(2);
        }
        if (e.key === "ArrowDown") {
          e.preventDefault();
          adjustHeight(-2);
        }
      }
      // Ctrl + 上下 : 调整位置 (上下移动)
      else if (e.ctrlKey && !e.altKey && !e.shiftKey) {
        if (e.key === "ArrowUp") {
          e.preventDefault();
          adjustPosition(2);
        }
        if (e.key === "ArrowDown") {
          e.preventDefault();
          adjustPosition(-2);
        }
      }
    },
    true,
  );
})();
