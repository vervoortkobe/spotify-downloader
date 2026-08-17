export interface Track {
  id: string
  title: string
  artists: string
  album: string
  cover: string
  releaseDate: string
  downloadLink: string
  sourceUrl?: string
}

export interface ServiceTheme {
  primary: string
  primaryLight: string
  primaryDark: string
  primaryBg: string
  primaryBgLight: string
  primaryText: string
  primaryTextLight: string
  primaryTextMuted: string
  border: string
  borderLight: string
  borderSubtle: string
  bgCard: string
  bgCardLight: string
  bgCardLighter: string
  glowRgba: string
  progressBg: string
  progressBar: string
  shadowRgba: string
  gradient1: string
  gradient2: string
  glow: string
  btn: string
}
