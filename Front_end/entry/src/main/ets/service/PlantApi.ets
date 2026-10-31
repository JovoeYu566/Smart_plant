import { AlarmEvent, HistoryPage, PlantLatest } from '../model/Models'
import { PlantMapper } from '../common/PlantMapper'
import { HttpClient } from './HttpClient'

export class PlantApi {
  static async latest(): Promise<PlantLatest | null> {
    const raw = await HttpClient.get('/api/plant/latest')
    let mapped = PlantMapper.normalizeLatest(raw)
    if (mapped === null || (mapped.gasAdc === undefined && mapped.agvTemperature === undefined
      && mapped.cargoCount === undefined && mapped.agvDistFront === undefined)) {
      try {
        const hist = await PlantApi.history(1, 1)
        if (hist.records.length > 0) {
          mapped = hist.records[0]
        }
      } catch (_e) {
        // keep mapped
      }
    }
    return mapped
  }

  static async history(page: number = 1, size: number = 30, keyword: string = ''): Promise<HistoryPage> {
    let path = `/api/plant/history?page=${page}&size=${size}`
    if (keyword.length > 0) {
      path = `${path}&keyword=${encodeURIComponent(keyword)}`
    }
    const raw = await HttpClient.get(path)
    if (raw === null) {
      const empty: HistoryPage = { records: [], total: 0, page: page, size: size }
      return empty
    }
    return PlantMapper.normalizeHistory(raw)
  }

  static async alarms(activeOnly: boolean = true, limit: number = 2000,
    keyword: string = ''): Promise<AlarmEvent[]> {
    let path = `/api/alarms?activeOnly=${activeOnly}&limit=${limit}`
    if (keyword.length > 0) {
      path = `${path}&keyword=${encodeURIComponent(keyword)}`
    }
    const raw = await HttpClient.get(path)
    const list: AlarmEvent[] = []
    if (raw !== null && Array.isArray(raw)) {
      for (let i = 0; i < raw.length; i++) {
        list.push(PlantMapper.normalizeAlarm(raw[i] as object))
      }
    }
    return list
  }

  static health(): Promise<object | null> {
    return HttpClient.get('/api/health', false)
  }
}
