import { ControlCommandBody, ControlLog, ControlResult } from '../model/Models'
import { HttpClient } from './HttpClient'

export class ControlApi {
  static async send(action: string): Promise<ControlResult> {
    const body: ControlCommandBody = {
      action: action
    }
    const raw = await HttpClient.post('/api/control/command', body)
    if (raw === null) {
      throw new Error('控制指令无返回')
    }
    const o = raw as Record<string, Object | number | boolean | string>
    const result: ControlResult = {
      requestId: o['requestId'] !== undefined ? `${o['requestId']}` : '',
      action: o['action'] !== undefined ? `${o['action']}` : action,
      topic: o['topic'] !== undefined ? `${o['topic']}` : '',
      success: o['success'] === true,
      message: o['message'] !== undefined ? `${o['message']}` : '已下发'
    }
    return result
  }

  static async history(limit: number = 30): Promise<ControlLog[]> {
    const raw = await HttpClient.get(`/api/control/history?limit=${limit}`)
    const list: ControlLog[] = []
    if (raw !== null && Array.isArray(raw)) {
      for (let i = 0; i < raw.length; i++) {
        const o = raw[i] as Record<string, Object | number | boolean | string | null>
        const item: ControlLog = {
          id: o['id'] !== undefined && o['id'] !== null ? Number(o['id']) : undefined,
          requestId: o['requestId'] !== undefined ? `${o['requestId']}` : undefined,
          action: o['action'] !== undefined ? `${o['action']}` : undefined,
          operator: o['operator'] !== undefined ? `${o['operator']}` : undefined,
          success: o['success'] === true,
          errorMessage: o['errorMessage'] !== undefined && o['errorMessage'] !== null ? `${o['errorMessage']}` : undefined,
          createdAt: o['createdAt'] !== undefined ? `${o['createdAt']}` : undefined
        }
        list.push(item)
      }
    }
    return list
  }
}
