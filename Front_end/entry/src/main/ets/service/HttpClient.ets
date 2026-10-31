import { http } from '@kit.NetworkKit'
import { PrefStore } from '../store/PrefStore'
import { ErrorUtil } from '../common/ErrorUtil'
import { AuthSession } from '../common/AuthSession'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x3200

export class HttpClient {
  static async request(method: http.RequestMethod, path: string, body?: object,
    needAuth: boolean = true): Promise<object | null> {
    const baseUrl = await PrefStore.getBaseUrl()
    const url = `${baseUrl}${path}`
    const header: Record<string, string> = {}
    header['Content-Type'] = 'application/json'
    header['Accept'] = 'application/json'
    if (needAuth) {
      const token = await PrefStore.getToken()
      if (token.length > 0) {
        header['Authorization'] = `Bearer ${token}`
      } else {
        AuthSession.notifyUnauthorized()
        throw new Error('未登录或 token 丢失，请重新登录')
      }
    }

    const client = http.createHttp()
    try {
      const options: http.HttpRequestOptions = {
        method: method,
        header: header,
        expectDataType: http.HttpDataType.STRING,
        // 花生壳外网抖动大；平板模拟器 DNS/链路更慢，过短会登录超时而手机偶发能通
        connectTimeout: 15000,
        readTimeout: 20000
      }
      if (body !== undefined) {
        options.extraData = JSON.stringify(body)
      }
      const resp = await client.request(url, options)
      const httpCode = resp.responseCode
      let raw: string
      if (typeof resp.result === 'string') {
        raw = resp.result as string
      } else if (resp.result === undefined || resp.result === null) {
        raw = ''
      } else {
        raw = JSON.stringify(resp.result)
      }
      hilog.info(DOMAIN, 'HttpClient', 'HTTP %{public}s %{public}d len=%{public}d', path, httpCode, raw.length)
      if (httpCode === 401 || httpCode === 403) {
        if (needAuth) {
          await PrefStore.clearAuth()
          AuthSession.notifyUnauthorized()
        }
        throw new Error('登录已失效（HTTP ' + httpCode + '），请重新登录')
      }
      if (httpCode < 200 || httpCode >= 300) {
        throw new Error(`HTTP ${httpCode}: ${raw.substring(0, 200)}`)
      }
      if (raw.length === 0) {
        throw new Error(`空响应: ${url}`)
      }
      const parsed = JSON.parse(raw) as Record<string, Object | number | string | null>
      const bizCode = Number(parsed['code'])
      const msg = parsed['msg'] !== undefined && parsed['msg'] !== null ? `${parsed['msg']}` : '业务错误'
      if (bizCode !== 0) {
        throw new Error(msg)
      }
      const data = parsed['data']
      if (data === undefined || data === null) {
        return null
      }
      return JSON.parse(JSON.stringify(data)) as object
    } catch (e) {
      if (e instanceof Error) {
        hilog.error(DOMAIN, 'HttpClient', 'ERR %{public}s %{public}s', path, e.message)
        throw new Error(e.message)
      }
      throw new Error(ErrorUtil.message(e as Object) + `（${url}）`)
    } finally {
      client.destroy()
    }
  }

  static get(path: string, needAuth: boolean = true): Promise<object | null> {
    return HttpClient.request(http.RequestMethod.GET, path, undefined, needAuth)
  }

  static post(path: string, body?: object, needAuth: boolean = true): Promise<object | null> {
    return HttpClient.request(http.RequestMethod.POST, path, body, needAuth)
  }
}
