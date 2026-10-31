import { window } from '@kit.ArkUI'

export interface EdgeInsets {
  top: number
  left: number
  right: number
  bottom: number
}

/** 全屏布局下读取避让区，并按主题设置系统栏颜色 */
export class SafeAreaUtil {
  static resolveTopInset(ctx: Context, onResult: (vp: number) => void): void {
    SafeAreaUtil.resolveInsets(ctx, (top: number, _bottom: number) => {
      onResult(top)
    })
  }

  static resolveInsets(ctx: Context, onResult: (topVp: number, bottomVp: number) => void): void {
    SafeAreaUtil.resolveEdgeInsets(ctx, (e: EdgeInsets) => {
      onResult(e.top, e.bottom)
    })
  }

  /** 综合系统栏 + 挖孔/刘海，得到四边避让（vp） */
  static resolveEdgeInsets(ctx: Context, onResult: (insets: EdgeInsets) => void): void {
    try {
      window.getLastWindow(ctx).then((win: window.Window) => {
        const sys = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
        const cut = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT)
        let winW = 0
        try {
          winW = win.getWindowProperties().windowRect.width
        } catch (_e) {
          winW = 0
        }
        const top = Math.max(
          px2vp(sys.topRect.height),
          px2vp(cut.topRect.height),
          SafeAreaUtil.cornerCutoutExtent(cut.topRect, winW, true)
        )
        const bottom = Math.max(px2vp(sys.bottomRect.height), px2vp(cut.bottomRect.height))
        let left = Math.max(
          px2vp(sys.leftRect.width),
          px2vp(cut.leftRect.width),
          SafeAreaUtil.cornerCutoutExtent(cut.topRect, winW, false),
          SafeAreaUtil.cornerCutoutExtent(cut.leftRect, winW, false)
        )
        // 部分机型把角落挖孔报成「通栏顶带」且 left=0，按顶带高度再让出左侧
        if (left <= 0 && winW > 0 && cut.topRect.height > 0 && cut.topRect.width >= winW * 0.8) {
          left = px2vp(cut.topRect.height) + 8
        }
        const right = Math.max(
          px2vp(sys.rightRect.width),
          px2vp(cut.rightRect.width),
          SafeAreaUtil.rightCornerFromTop(cut.topRect, winW)
        )
        onResult({
          top: top > 0 ? top : 0,
          left: left > 0 ? left : 0,
          right: right > 0 ? right : 0,
          bottom: bottom > 0 ? bottom : 0
        })
      }).catch(() => {
        onResult({ top: 36, left: 0, right: 0, bottom: 16 })
      })
    } catch (_e) {
      onResult({ top: 36, left: 0, right: 0, bottom: 16 })
    }
  }

  /**
   * 角落挖孔常落在 topRect：宽高都不大时，用 left+width 作为左侧让位，
   * 或用 height 作为顶部让位。
   */
  private static cornerCutoutExtent(rect: window.Rect, winWPx: number, forTop: boolean): number {
    if (rect.width <= 0 || rect.height <= 0) {
      return 0
    }
    const isLocalHole = winWPx <= 0 || rect.width < winWPx * 0.35
    if (!isLocalHole) {
      return forTop ? px2vp(rect.height) : 0
    }
    if (forTop) {
      return px2vp(rect.top + rect.height)
    }
    // 左上角挖孔：right edge of hole
    if (rect.left <= winWPx * 0.25 || winWPx <= 0) {
      return px2vp(rect.left + rect.width)
    }
    return 0
  }

  private static rightCornerFromTop(rect: window.Rect, winWPx: number): number {
    if (winWPx <= 0 || rect.width <= 0 || rect.height <= 0) {
      return 0
    }
    if (rect.width >= winWPx * 0.35) {
      return 0
    }
    // 右上角挖孔
    if (rect.left > winWPx * 0.5) {
      return px2vp(winWPx - rect.left)
    }
    return 0
  }

  /**
   * @param darkImmersive 深色大屏用浅色系统图标
   * @param hideStatusBar 隐藏系统状态栏（用应用内时钟替代系统时间）
   */
  static applySystemBarStyle(ctx: Context, darkImmersive: boolean, hideStatusBar: boolean = false): void {
    SafeAreaUtil.applySystemBarStyleAsync(ctx, darkImmersive, hideStatusBar).then(() => {
    }).catch(() => {
    })
  }

  static async applySystemBarStyleAsync(ctx: Context, darkImmersive: boolean,
    hideStatusBar: boolean = false): Promise<void> {
    try {
      const win = await window.getLastWindow(ctx)
      await win.setWindowLayoutFullScreen(true)
      const names: Array<'status' | 'navigation'> = hideStatusBar
        ? ['navigation']
        : ['status', 'navigation']
      await win.setWindowSystemBarEnable(names)
      const contentColor = darkImmersive ? '#E8F4FF' : '#1A2332'
      const props: window.SystemBarProperties = {
        statusBarColor: '#00000000',
        statusBarContentColor: contentColor,
        navigationBarColor: '#00000000',
        navigationBarContentColor: contentColor
      }
      await win.setWindowSystemBarProperties(props)
    } catch (_e) {
      // ignore
    }
  }
}
