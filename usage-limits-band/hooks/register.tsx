import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Limit } from '../types'

const limits = atom({ plugin: 'usage-limits-band', key: 'limits' } as const, [])

const LABELS: Record<string, string> = { five_hour: '5h', seven_day: '7d' }
const RING_PX = 14

const label = (kind: string) => LABELS[kind] ?? kind.replace(/_/g, ' ')
const tone = (percent: number) => (percent >= 95 ? 'error' : percent >= 80 ? 'warning' : undefined)

// Drawn as an image, so it cannot follow the theme: a translucent track reads on light and dark.
const ring = (percent: number) => {
  const color = percent >= 95 ? '#e5484d' : percent >= 80 ? '#e0a030' : '#2f7de1'
  const r = 5
  const c = 2 * Math.PI * r
  const filled = (Math.min(percent, 100) / 100) * c
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${RING_PX}" height="${RING_PX}" viewBox="0 0 ${RING_PX} ${RING_PX}">` +
    `<circle cx="7" cy="7" r="${r}" fill="none" stroke="#808080" stroke-opacity="0.3" stroke-width="2.5"/>` +
    `<circle cx="7" cy="7" r="${r}" fill="none" stroke="${color}" stroke-width="2.5" stroke-linecap="round" ` +
    `stroke-dasharray="${filled.toFixed(2)} ${c.toFixed(2)}" transform="rotate(-90 7 7)"/></svg>`
  )
}

const until = (iso: string, now: number) => {
  const minutes = Math.max(0, Math.round((Date.parse(iso) - now) / 60_000))
  if (minutes < 60) return `${minutes}m`
  if (minutes < 1440) return `${Math.floor(minutes / 60)}h ${minutes % 60}m`
  return `${Math.floor(minutes / 1440)}d ${Math.floor((minutes % 1440) / 60)}h`
}

type Reading = { kind: string; percentUsed: number; resetsAt?: string }

async function save($: EngineInterface, rateLimits: Reading[]) {
  const next: Limit[] = rateLimits.map(r => ({
    kind: r.kind,
    percent: r.percentUsed,
    resetsAt: r.resetsAt ?? null,
  }))
  await update($, limits, () => next)
}

export const register: Register = on => {
  on('session.measure', async ($, e, next) => {
    await save($, e.rateLimits)

    return next(e)
  })

  on('session.attach', { surface: 'desktop' }, async ($, e, next) => {
    const attached = await next(e)
    const usage = await $.session.usage()
    await save($, usage.rateLimits)

    return attached
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.surface !== 'desktop' || e.props.hasSurvey) return next(e)

    const shown = await read($, limits)
    if (shown.length === 0) return next(e)

    const now = await $.clock.now()
    const { Box, Svg, Text } = $.ui.resolve(e)

    return (
      <Box flexDirection="row" justifyContent="flex-end" columnGap={3}>
        {shown.map(l => (
          <Box key={l.kind} flexDirection="row" alignItems="center" columnGap={1}>
            <Svg source={ring(l.percent)} alt={`${label(l.kind)} ${l.percent}% used`} width={RING_PX} height={RING_PX} />
            <Text color={tone(l.percent)} dimColor={tone(l.percent) === undefined}>
              {`${label(l.kind)} ${l.percent}%${l.resetsAt ? ` ↻ ${until(l.resetsAt, now)}` : ''}`}
            </Text>
          </Box>
        ))}
      </Box>
    )
  })
}
