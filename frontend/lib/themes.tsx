import { SiSpotify, SiYoutube, SiSoundcloud } from "react-icons/si"
import type { ServiceTheme } from "./types"

export const serviceLabels: Record<string, string> = {
  auto: "Auto-detect",
  spotify: "Spotify",
  youtube: "YouTube",
  soundcloud: "SoundCloud",
}

export const serviceIcons: Record<string, JSX.Element> = {
  spotify: <SiSpotify className="h-5 w-5 text-[#1DB954]" />,
  youtube: <SiYoutube className="h-5 w-5 text-[#FF0000]" />,
  soundcloud: <SiSoundcloud className="h-5 w-5 text-[#FF7700]" />,
}

export const detectServiceFromUrl = (url: string): string | null => {
  if (/open\.spotify\.com/.test(url)) return "spotify"
  if (/(youtube\.com|youtu\.be)/.test(url)) return "youtube"
  if (/soundcloud\.com/.test(url)) return "soundcloud"
  return null
}

export const serviceTheme: Record<string, ServiceTheme> = {
  spotify: {
    primary: "#10b981",
    primaryLight: "#34d399",
    primaryDark: "#047857",
    primaryBg: "#064e3b",
    primaryBgLight: "#022c22",
    primaryText: "#ecfdf5",
    primaryTextLight: "#a7f3d0",
    primaryTextMuted: "#6ee7b7",
    border: "rgba(6,78,59,0.6)",
    borderLight: "rgba(6,78,59,0.7)",
    borderSubtle: "rgba(5,46,22,0.6)",
    bgCard: "#09120d",
    bgCardLight: "#08110c",
    bgCardLighter: "#0d1913",
    glowRgba: "rgba(6,95,70,0.25)",
    progressBg: "#0f1f16",
    progressBar: "#047857",
    shadowRgba: "rgba(6,95,70,0.2)",
    gradient1: "rgba(0,70,45,0.5)",
    gradient2: "rgba(0,100,50,0.35)",
    glow: "bg-emerald-900/20",
    btn: "border-emerald-700/70 bg-emerald-900/80 text-emerald-50 shadow-[0_0_20px_rgba(6,95,70,0.25)] hover:bg-emerald-800/85",
  },
  youtube: {
    primary: "#ef4444",
    primaryLight: "#f87171",
    primaryDark: "#b91c1c",
    primaryBg: "#7f1d1d",
    primaryBgLight: "#450a0a",
    primaryText: "#fef2f2",
    primaryTextLight: "#fca5a5",
    primaryTextMuted: "#f87171",
    border: "rgba(127,29,29,0.6)",
    borderLight: "rgba(127,29,29,0.7)",
    borderSubtle: "rgba(69,10,10,0.6)",
    bgCard: "#120909",
    bgCardLight: "#110808",
    bgCardLighter: "#1a0d0d",
    glowRgba: "rgba(239,68,68,0.25)",
    progressBg: "#1f0f0f",
    progressBar: "#b91c1c",
    shadowRgba: "rgba(239,68,68,0.2)",
    gradient1: "rgba(127,29,29,0.5)",
    gradient2: "rgba(180,30,30,0.35)",
    glow: "bg-red-900/20",
    btn: "border-red-700/70 bg-red-900/80 text-red-50 shadow-[0_0_20px_rgba(239,68,68,0.25)] hover:bg-red-800/85",
  },
  soundcloud: {
    primary: "#ff7700",
    primaryLight: "#ff9933",
    primaryDark: "#e06000",
    primaryBg: "#cc5500",
    primaryBgLight: "#7a2e00",
    primaryText: "#fff7ed",
    primaryTextLight: "#fed7aa",
    primaryTextMuted: "#ff8c42",
    border: "rgba(255,119,0,0.6)",
    borderLight: "rgba(255,119,0,0.7)",
    borderSubtle: "rgba(224,96,0,0.6)",
    bgCard: "#120a05",
    bgCardLight: "#110904",
    bgCardLighter: "#1a0e06",
    glowRgba: "rgba(255,119,0,0.3)",
    progressBg: "#1f1006",
    progressBar: "#ff7700",
    shadowRgba: "rgba(255,119,0,0.2)",
    gradient1: "rgba(200,80,0,0.5)",
    gradient2: "rgba(255,119,0,0.35)",
    glow: "bg-orange-900/20",
    btn: "border-orange-600/80 bg-orange-700/90 text-orange-50 shadow-[0_0_20px_rgba(255,119,0,0.3)] hover:bg-orange-600/85",
  },
}
