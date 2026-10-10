export type Limit = { kind: string; percent: number; resetsAt: string | null }

declare module 'claude-code' {
  interface PluginState {
    'usage-limits-band': {
      limits: Limit[]
    }
  }
}
