import { LoginData, LoginRequest } from '../model/Models'
import { PrefStore } from '../store/PrefStore'
import { HttpClient } from './HttpClient'

export class AuthApi {
  static async login(username: string, password: string): Promise<LoginData> {
    const req: LoginRequest = {
      username: username,
      password: password
    }
    const raw = await HttpClient.post('/api/auth/login', req, false)
    if (raw === null) {
      throw new Error('登录返回为空')
    }
    const o = raw as Record<string, Object | number | string>
    const token = o['token'] !== undefined ? `${o['token']}` : ''
    if (token.length === 0) {
      throw new Error('登录未返回 token')
    }
    const data: LoginData = {
      token: token,
      tokenType: o['tokenType'] !== undefined ? `${o['tokenType']}` : 'Bearer',
      expireHours: Number(o['expireHours'] ?? 24),
      username: o['username'] !== undefined ? `${o['username']}` : username,
      displayName: o['displayName'] !== undefined ? `${o['displayName']}` : username
    }
    await PrefStore.setToken(data.token)
    await PrefStore.setUsername(data.username)
    return data
  }

  static async logout(): Promise<void> {
    await PrefStore.clearAuth()
  }

  static async isLoggedIn(): Promise<boolean> {
    const token = await PrefStore.getToken()
    return token.length > 0
  }
}
