import { BusinessError } from '@kit.BasicServicesKit'

export class ErrorUtil {
  static message(e: Object): string {
    if (e === null || e === undefined) {
      return '未知错误'
    }
    if (typeof e === 'string') {
      return e
    }
    const anyErr = e as Record<string, Object>
    if (anyErr['message'] !== undefined && anyErr['message'] !== null) {
      return `${anyErr['message']}`
    }
    try {
      const be = e as BusinessError
      if (be.code !== undefined) {
        return `网络错误 code=${be.code} ${be.message ?? ''}`
      }
    } catch (_ignore) {
      // ignore
    }
    try {
      return JSON.stringify(e)
    } catch (_ignore2) {
      return '请求失败，请检查后端地址与网络'
    }
  }
}
