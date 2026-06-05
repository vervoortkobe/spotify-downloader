"use client"

import { useEffect, useRef, useState } from "react"
import {
  Check,
  Music2,
  Download,
  Loader2,
  Sparkles,
  Search,
  Square,
  Play,
  Pause,
  Pencil,
  X,
  RotateCcw,
  ExternalLink,
  Radio,
  ChevronDown,
} from "lucide-react"
import { SiSpotify, SiYoutube, SiSoundcloud } from "react-icons/si"
import { Progress } from "@/components/ui/progress"
import { ScrollArea } from "@/components/ui/scroll-area"
import { toast, Toaster } from "react-hot-toast"
import Image from "next/image"

interface Track {
  id: string
  title: string
  artists: string
  album: string
  cover: string
  releaseDate: string
  downloadLink: string
  sourceUrl?: string
}

const getApiUrl = () => {
  if (process.env.NEXT_PUBLIC_API_URL) {
    const url = process.env.NEXT_PUBLIC_API_URL.replace(/\/+$/, "").replace(/\/api$/, "")
    return url.match(/^https?:\/\/|^\/\//) ? url : `https://${url}`
  }

  if (typeof window !== "undefined") {
    const { protocol, hostname } = window.location
    const port = hostname === "localhost" || hostname === "127.0.0.1" ? ":5000" : ""
    return `${protocol}//${hostname}${port}`
  }
}

let LOCAL_API = getApiUrl()

export default function SpotifyDownloaderApp() {
  const [playlistLink, setPlaylistLink] = useState("")

  const [backendOnline, setBackendOnline] = useState<boolean | null>(null)

  useEffect(() => {
    setPlaylistLink("")
  }, [])

  useEffect(() => {
    LOCAL_API = getApiUrl()

    const checkHealth = async () => {
      console.log(`[Health Check] Polling backend health at ${LOCAL_API}/api/health...`)
      try {
        const controller = new AbortController()
        const timeoutId = setTimeout(() => controller.abort(), 4000)
        const res = await fetch(`${LOCAL_API}/api/health`, { signal: controller.signal })
        clearTimeout(timeoutId)
        if (res.ok) {
          const data = await res.json()
          if (data.online) {
            setBackendOnline(true)
            console.log("[Health Check] Backend is online!")
            return
          }
        }
        setBackendOnline(false)
        console.log("[Health Check] Backend returned non-OK status or not online.")
      } catch (e: any) {
        setBackendOnline(false)
        if (e?.name === "AbortError") {
          console.warn("[Health Check] Health check request timed out.")
        } else {
          console.error("[Health Check] Failed to reach backend:", e)
        }
      }
    }

    checkHealth()
  }, [])

  const [downloadProgress, setDownloadProgress] = useState(0)
  const [songsDownloaded, setSongsDownloaded] = useState(0)
  const [totalSongs, setTotalSongs] = useState(0)
  const [playlistName, setPlaylistName] = useState("")
  const [isProcessing, setIsProcessing] = useState(false)
  const [statusMessage, setStatusMessage] = useState("Paste a Spotify URL to begin")
  const [tracks, setTracks] = useState<Track[]>([])
  const [selectedTrack, setSelectedTrack] = useState<Track | null>(null)
  const [selectedTrackIds, setSelectedTrackIds] = useState<string[]>([])
  const [isDownloadingTrack, setIsDownloadingTrack] = useState<string | null>(null)
  const [activeAbortController, setActiveAbortController] = useState<AbortController | null>(null)
  const [isDownloadingAll, setIsDownloadingAll] = useState(false)
  const [activePlaylistJobId, setActivePlaylistJobId] = useState<string | null>(null)
  const [playlistDownloadProgress, setPlaylistDownloadProgress] = useState(0)
  const [trackProgress, setTrackProgress] = useState<Record<string, number>>({})
  const trackProgressIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const playlistProgressIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const playlistStartAbortRef = useRef<AbortController | null>(null)
  const playlistStatusAbortRef = useRef<AbortController | null>(null)
  const playlistCancelRequestedRef = useRef(false)

  // Source URL override state
  const [urlOverrides, setUrlOverrides] = useState<Record<string, string>>({})
  const [isEditingUrl, setIsEditingUrl] = useState(false)
  const [urlDraft, setUrlDraft] = useState("")
  const [isResolvingUrl, setIsResolvingUrl] = useState(false)
  const [urlMeta, setUrlMeta] = useState<
    Record<string, { title: string; channel: string; thumbnail: string; duration: number } | null>
  >({})

  // Service selector state
  const [selectedService, setSelectedService] = useState<string>("auto")
  const [fetchedService, setFetchedService] = useState<string>("spotify")
  const [showServiceDropdown, setShowServiceDropdown] = useState(false)
  const serviceDropdownRef = useRef<HTMLDivElement | null>(null)

  const serviceLabels: Record<string, string> = {
    auto: "Auto-detect",
    spotify: "Spotify",
    youtube: "YouTube",
    soundcloud: "SoundCloud",
  }

  const serviceIcons: Record<string, JSX.Element> = {
    spotify: <SiSpotify className="h-5 w-5 text-[#1DB954]" />,
    youtube: <SiYoutube className="h-5 w-5 text-[#FF0000]" />,
    soundcloud: <SiSoundcloud className="h-5 w-5 text-[#FF7700]" />,
  }

  const detectServiceFromUrl = (url: string): string | null => {
    if (/open\.spotify\.com/.test(url)) return "spotify"
    if (/(youtube\.com|youtu\.be)/.test(url)) return "youtube"
    if (/soundcloud\.com/.test(url)) return "soundcloud"
    return null
  }

  const detectedService = detectServiceFromUrl(playlistLink)
  const effectiveService = selectedService === "auto" ? (detectedService || "spotify") : selectedService

  const serviceTheme: Record<
    string,
    {
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
  > = {
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

  const t = serviceTheme[effectiveService]

  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (serviceDropdownRef.current && !serviceDropdownRef.current.contains(e.target as Node)) {
        setShowServiceDropdown(false)
      }
    }
    document.addEventListener("mousedown", handleClickOutside)
    return () => document.removeEventListener("mousedown", handleClickOutside)
  }, [])

  // Streaming state
  const [streamingTrackId, setStreamingTrackId] = useState<string | null>(null)
  const [isLoadingStream, setIsLoadingStream] = useState(false)
  const [isPlaying, setIsPlaying] = useState(false)
  const [streamProgress, setStreamProgress] = useState(0) // 0-1
  const [streamDuration, setStreamDuration] = useState(0)
  const audioRef = useRef<HTMLAudioElement | null>(null)

  const progressBarClassName = "h-3 bg-[var(--clr-progressBg)] [&>div]:bg-[var(--clr-progressBar)] rounded-full"
  const allTracksSelected = tracks.length > 0 && selectedTrackIds.length === tracks.length
  const selectedDownloadTracks = tracks.filter((track) => selectedTrackIds.includes(track.id))

  const clearTrackProgressInterval = () => {
    if (trackProgressIntervalRef.current) {
      clearInterval(trackProgressIntervalRef.current)
      trackProgressIntervalRef.current = null
    }
  }

  const clearPlaylistProgressInterval = () => {
    if (playlistProgressIntervalRef.current) {
      clearInterval(playlistProgressIntervalRef.current)
      playlistProgressIntervalRef.current = null
    }
  }

  useEffect(() => {
    setSelectedTrackIds(tracks.map((track) => track.id))
  }, [tracks])

  useEffect(() => {
    if (tracks.length === 0) {
      document.body.style.overflow = "hidden"
    } else {
      document.body.style.overflow = "unset"
    }
    return () => {
      document.body.style.overflow = "unset"
    }
  }, [tracks.length])

  const toggleTrackSelection = (trackId: string) => {
    setSelectedTrackIds((prev) =>
      prev.includes(trackId) ? prev.filter((id) => id !== trackId) : [...prev, trackId]
    )
  }

  const toggleAllTrackSelection = () => {
    setSelectedTrackIds(allTracksSelected ? [] : tracks.map((track) => track.id))
  }

  const getPlaylistProgress = (progressByTrack: Record<string, number>) => {
    if (selectedDownloadTracks.length === 0) return 0

    const total = selectedDownloadTracks.reduce((sum, track) => {
      const progress = progressByTrack[track.id] ?? 0
      return sum + Math.max(0, Math.min(100, progress))
    }, 0)

    return total / selectedDownloadTracks.length
  }

  const sleep = (ms: number, signal?: AbortSignal) =>
    new Promise<void>((resolve) => {
      const timeoutId = window.setTimeout(() => {
        cleanup()
        resolve()
      }, ms)

      const cleanup = () => {
        window.clearTimeout(timeoutId)
        signal?.removeEventListener("abort", onAbort)
      }

      const onAbort = () => {
        cleanup()
        resolve()
      }

      if (signal) {
        signal.addEventListener("abort", onAbort, { once: true })
      }
    })

  const cancelTrackDownload = async (trackId: string) => {
    if (isDownloadingTrack !== trackId) return
    clearTrackProgressInterval()
    activeAbortController?.abort()

    try {
      await fetch(`${LOCAL_API}/api/cancel-track/${trackId}`, { method: "POST" })
    } catch (e) {
      console.error("Failed to notify backend about track cancellation", e)
    }
  }

  // ---- YouTube URL management ----

  const startEditingUrl = (track: Track) => {
    setIsEditingUrl(true)
    setUrlDraft(urlOverrides[track.id] || "")
  }

  const cancelEditingUrl = () => {
    setIsEditingUrl(false)
    setUrlDraft("")
  }

  const resetUrl = (trackId: string) => {
    setUrlOverrides((prev) => {
      const n = { ...prev }
      delete n[trackId]
      return n
    })
    setUrlMeta((prev) => {
      const n = { ...prev }
      delete n[trackId]
      return n
    })
    setIsEditingUrl(false)
    setUrlDraft("")
    toast.success("Reset to auto-detected source")
  }

  const saveUrl = async (track: Track) => {
    const url = urlDraft.trim()
    if (!url) {
      toast.error("Please enter a URL")
      return
    }
    if (!(url.startsWith("https://") || url.startsWith("http://"))) {
      toast.error("URL must start with http:// or https://")
      return
    }
    setIsResolvingUrl(true)
    try {
      const res = await fetch(`${LOCAL_API}/api/resolve-youtube-url`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ youtubeUrl: url }),
      })
      if (!res.ok) {
        const err = await res.json().catch(() => ({}))
        throw new Error(err.error || "Could not resolve URL")
      }
      const meta = await res.json()
      setUrlOverrides((prev) => ({ ...prev, [track.id]: url }))
      setUrlMeta((prev) => ({ ...prev, [track.id]: meta }))
      setIsEditingUrl(false)
      setUrlDraft("")
      toast.success("Source updated")
    } catch (err: any) {
      toast.error(err.message || "Failed to resolve URL")
    } finally {
      setIsResolvingUrl(false)
    }
  }

  // ---- Audio streaming ----

  const stopStream = () => {
    const audio = audioRef.current
    if (audio) {
      audio.onerror = null
      audio.onloadedmetadata = null
      audio.ontimeupdate = null
      audio.onended = null
      audio.pause()
      audio.src = ""
      audio.load()
    }
    setStreamingTrackId(null)
    setIsPlaying(false)
    setIsLoadingStream(false)
    setStreamProgress(0)
    setStreamDuration(0)
  }

  const toggleStream = async (track: Track) => {
    if (streamingTrackId === track.id && audioRef.current) {
      if (isPlaying) {
        audioRef.current.pause()
        setIsPlaying(false)
      } else {
        audioRef.current.play()
        setIsPlaying(true)
      }
      return
    }

    stopStream()

    setStreamingTrackId(track.id)
    setIsLoadingStream(true)

    try {
      const sourceUrl = urlOverrides[track.id] || track.sourceUrl || ""
      const params = new URLSearchParams()
      if (sourceUrl) {
        params.set("source_url", sourceUrl)
      } else {
        params.set("title", track.title)
        params.set("artists", track.artists)
      }
      const streamUrl = `${LOCAL_API}/api/stream?${params.toString()}`

      if (!audioRef.current) {
        audioRef.current = new Audio()
      }
      const audio = audioRef.current
      audio.src = streamUrl
      audio.onloadedmetadata = () => {
        setStreamDuration(audio.duration || 0)
        setIsLoadingStream(false)
      }
      audio.ontimeupdate = () => {
        if (audio.duration) setStreamProgress(audio.currentTime / audio.duration)
      }
      audio.onended = () => {
        setIsPlaying(false)
        setStreamProgress(1)
      }
      audio.onerror = () => {
        toast.error("Stream error")
        stopStream()
      }
      await audio.play()
      setIsPlaying(true)
    } catch (err: any) {
      toast.error(err.message || "Failed to stream track")
      stopStream()
    } finally {
      setIsLoadingStream(false)
    }
  }

  const seekStream = (ratio: number) => {
    if (audioRef.current && streamDuration) {
      audioRef.current.currentTime = ratio * streamDuration
      setStreamProgress(ratio)
    }
  }

  // Cleanup audio on unmount
  useEffect(() => {
    return () => {
      stopStream()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const cancelPlaylistDownload = async () => {
    playlistCancelRequestedRef.current = true
    clearPlaylistProgressInterval()
    playlistStartAbortRef.current?.abort()
    playlistStatusAbortRef.current?.abort()
    toast.loading("Cancelling playlist download...", { id: "download-toast" })

    try {
      if (!activePlaylistJobId) {
        return
      }
      await fetch(`${LOCAL_API}/api/cancel-playlist/${activePlaylistJobId}`, { method: "POST" })
      toast.success("Playlist download cancelled", { id: "download-toast" })
    } catch (e) {
      console.error("Failed to notify backend about playlist cancellation", e)
      toast.error("Failed to cancel playlist download", { id: "download-toast" })
    }
  }

  const downloadTrack = async (track: Track) => {
    try {
      setIsDownloadingTrack(track.id)
      setTrackProgress((prev) => ({ ...prev, [track.id]: 0 }))

      const controller = new AbortController()
      setActiveAbortController(controller)

      clearTrackProgressInterval()
      trackProgressIntervalRef.current = setInterval(async () => {
        try {
          const res = await fetch(`${LOCAL_API}/api/progress/${track.id}`)
          if (res.ok) {
            const data = await res.json()
            setTrackProgress((prev) => ({ ...prev, [track.id]: data.progress || 0 }))
          }
        } catch (e) {}
      }, 500)

      const sourceUrl = urlOverrides[track.id] || track.sourceUrl || ""
      const response = await fetch(`${LOCAL_API}/api/download-track`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ...track, sourceUrl }),
      })

      clearTrackProgressInterval()
      setTrackProgress((prev) => ({ ...prev, [track.id]: 100 }))

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}))
        throw new Error(errorData.message || "Download failed")
      }

      const blob = await response.blob()
      const url = window.URL.createObjectURL(blob)
      const a = document.createElement("a")
      a.href = url
      a.download = `${track.title} - ${track.artists}.mp3`
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      window.URL.revokeObjectURL(url)
      toast.success(`Downloaded ${track.title}`)

      setTimeout(() => {
        setTrackProgress((prev) => {
          if (prev[track.id] === -1) return prev
          const newState = { ...prev }
          delete newState[track.id]
          return newState
        })
      }, 1500)
    } catch (err: any) {
      clearTrackProgressInterval()

      if (err.name === "AbortError") {
        fetch(`${LOCAL_API}/api/cancel-track/${track.id}`, { method: "POST" }).catch(() => {})
        toast.error(`Cancelled ${track.title}`)
        setTrackProgress((prev) => {
          const newState = { ...prev }
          delete newState[track.id]
          return newState
        })
      } else {
        console.error(err)
        toast.error(err.message || "Download failed")
        setTrackProgress((prev) => ({ ...prev, [track.id]: -1 }))
        setTimeout(() => {
          setTrackProgress((prev) => {
            const newState = { ...prev }
            delete newState[track.id]
            return newState
          })
        }, 5000)
      }
    } finally {
      setIsDownloadingTrack(null)
      setActiveAbortController(null)
    }
  }

  const downloadAll = async () => {
    if (selectedDownloadTracks.length === 0) {
      toast.error("Select at least one song to download")
      return
    }
    try {
      setIsDownloadingAll(true)
      setPlaylistDownloadProgress(0)
      setActivePlaylistJobId(null)
      playlistCancelRequestedRef.current = false
      playlistStartAbortRef.current = new AbortController()
      playlistStatusAbortRef.current = new AbortController()
      toast.loading("Downloading playlist, this might take a while...", { id: "download-toast" })

      setTrackProgress((prev) => {
        const ns = { ...prev }
        selectedDownloadTracks.forEach((track) => {
          ns[track.id] = 0
        })
        return ns
      })

      clearPlaylistProgressInterval()
      playlistProgressIntervalRef.current = setInterval(async () => {
        try {
          const res = await fetch(`${LOCAL_API}/api/progress/all`)
          if (res.ok) {
            const data = await res.json()
            setTrackProgress((prev) => {
              const ns = { ...prev }
              selectedDownloadTracks.forEach((t) => {
                if (data[t.id] !== undefined) {
                  ns[t.id] = data[t.id]
                }
              })
              setPlaylistDownloadProgress(getPlaylistProgress(ns))
              return ns
            })
          }
        } catch (e) {}
      }, 1000)

      const res = await fetch(`${LOCAL_API}/api/download-playlist-zip`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          tracks: selectedDownloadTracks.map((t) => ({
            ...t,
            sourceUrl: urlOverrides[t.id] || t.sourceUrl || "",
          })),
          playlistName,
        }),
        signal: playlistStartAbortRef.current?.signal,
      })

      if (!res.ok) {
        clearPlaylistProgressInterval()
        const errorData = await res.json().catch(() => ({}))
        throw new Error(errorData.message || "Failed to start playlist download")
      }

      const { job_id } = await res.json()
      if (!job_id) {
        clearPlaylistProgressInterval()
        throw new Error("No job ID received from server")
      }

      setActivePlaylistJobId(job_id)

      if (playlistCancelRequestedRef.current) {
        await fetch(`${LOCAL_API}/api/cancel-playlist/${job_id}`, { method: "POST" }).catch(
          () => {}
        )
        setTrackProgress({})
        setPlaylistDownloadProgress(0)
        toast.success("Playlist download cancelled", { id: "download-toast" })
        return
      }

      let jobFinished = false
      let success = false

      while (!jobFinished && !playlistCancelRequestedRef.current) {
        await sleep(2000, playlistStatusAbortRef.current?.signal)

        if (playlistCancelRequestedRef.current) {
          break
        }

        try {
          const statusRes = await fetch(`${LOCAL_API}/api/job-status/${job_id}`, {
            signal: playlistStatusAbortRef.current?.signal,
          })
          if (!statusRes.ok) continue

          const job = await statusRes.json()
          if (job.status === "completed") {
            jobFinished = true
            success = true
          } else if (job.status === "cancelled") {
            jobFinished = true
            toast.error("Playlist download cancelled", { id: "download-toast" })
          } else if (job.status === "error") {
            jobFinished = true
            throw new Error(job.message || "Background processing failed")
          } else {
            toast.loading("Downloading and zipping tracks...", { id: "download-toast" })
          }
        } catch (e: any) {
          if (playlistCancelRequestedRef.current || e?.name === "AbortError") {
            break
          }
          if (e.message.includes("Background processing failed")) throw e
        }
      }

      clearPlaylistProgressInterval()

      if (playlistCancelRequestedRef.current) {
        setTrackProgress({})
        setPlaylistDownloadProgress(0)
        return
      }

      if (success) {
        setPlaylistDownloadProgress(100)
        toast.loading("Finalizing ZIP file...", { id: "download-toast" })
        const downloadUrl = `${LOCAL_API}/api/download-job/${job_id}`

        const a = document.createElement("a")
        a.href = downloadUrl
        a.download = `${playlistName || "Playlist"}.zip`
        document.body.appendChild(a)
        a.click()
        document.body.removeChild(a)

        toast.success("Playlist downloaded", { id: "download-toast" })
      }

      setTimeout(() => {
        setTrackProgress({})
        setPlaylistDownloadProgress(0)
      }, 1500)
    } catch (err: any) {
      console.error(err)
      if (!playlistCancelRequestedRef.current) {
        toast.error(err.message || "Playlist download failed", { id: "download-toast" })
      }
      setTrackProgress({})
      setPlaylistDownloadProgress(0)
    } finally {
      clearPlaylistProgressInterval()
      playlistStartAbortRef.current?.abort()
      playlistStartAbortRef.current = null
      playlistStatusAbortRef.current?.abort()
      playlistStatusAbortRef.current = null
      setActivePlaylistJobId(null)
      setIsDownloadingAll(false)
      playlistCancelRequestedRef.current = false
    }
  }

  const handleProcess = async () => {
    if (!playlistLink) {
      toast.error("Please enter a URL")
      return
    }

    const detected = detectServiceFromUrl(playlistLink)
    if (!detected && selectedService === "auto") {
      toast.error("Unrecognized URL — please use Spotify, YouTube, or SoundCloud.")
      return
    }

    setIsProcessing(true)
    setFetchedService(effectiveService)
    setDownloadProgress(0)
    setSongsDownloaded(0)
    setTotalSongs(0)
    setStatusMessage("Fetching data...")
    setTracks([])
    setSelectedTrack(null)

    try {
      const response = await fetch(`${LOCAL_API}/api/scrape-playlist`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ playlistUrl: playlistLink, service: effectiveService }),
      })

      if (!response.ok) throw new Error("Failed to process playlist")

      const result = await response.json()

      if (result.event === "complete") {
        setPlaylistName(result.data.playlistName || "Playlist")
        const processedTracks: Track[] = result.data.tracks || []
        setTracks(processedTracks)
        setTotalSongs(processedTracks.length)
        setSongsDownloaded(processedTracks.length)
        setDownloadProgress(100)
        setStatusMessage(`Found ${processedTracks.length} tracks`)

        if (processedTracks.length > 0) {
          setSelectedTrack(processedTracks[0])
        }

        toast.success(`Loaded ${processedTracks.length} tracks!`)
      } else if (result.event === "error") {
        throw new Error(result.data?.message || "Processing failed")
      }
    } catch (error) {
      console.error("Error:", error)
      toast.error(error instanceof Error ? error.message : "Failed to process")
      setStatusMessage("Error - try again")
    } finally {
      setIsProcessing(false)
    }
  }

  return (
    <div
      className={`min-h-dvh bg-[#07110b] font-sans text-zinc-50 selection:bg-[var(--clr-primaryBg)]/40 ${tracks.length === 0 ? "h-dvh overflow-hidden" : ""}`}
      style={{
        "--clr-primary": t.primary,
        "--clr-primaryLight": t.primaryLight,
        "--clr-primaryDark": t.primaryDark,
        "--clr-primaryBg": t.primaryBg,
        "--clr-primaryBgLight": t.primaryBgLight,
        "--clr-primaryText": t.primaryText,
        "--clr-primaryTextLight": t.primaryTextLight,
        "--clr-primaryTextMuted": t.primaryTextMuted,
        "--clr-border": t.border,
        "--clr-borderLight": t.borderLight,
        "--clr-borderSubtle": t.borderSubtle,
        "--clr-bgCard": t.bgCard,
        "--clr-bgCardLight": t.bgCardLight,
        "--clr-bgCardLighter": t.bgCardLighter,
        "--clr-glowRgba": t.glowRgba,
        "--clr-progressBg": t.progressBg,
        "--clr-progressBar": t.progressBar,
        "--clr-shadowRgba": t.shadowRgba,
        "--clr-gradient1": t.gradient1,
        "--clr-gradient2": t.gradient2,
      } as React.CSSProperties}
    >
      {/* Background Gradient */}
      <div className="pointer-events-none fixed inset-0 z-0 overflow-hidden">
        <div className="absolute -left-[10%] -top-[25%] h-[80%] w-[80%] rounded-full bg-[var(--clr-gradient1)] mix-blend-screen blur-[140px]" />
        <div className="absolute -right-[10%] top-[20%] h-[60%] w-[60%] rounded-full bg-[var(--clr-gradient2)] mix-blend-screen blur-[140px]" />
      </div>

      <Toaster
        position="top-center"
        toastOptions={{
          style: {
            background: "#07110b",
            color: "#f4f4f5",
            border: `1px solid ${t.primary}33`,
            borderRadius: "1rem",
            boxShadow: `0 0 20px ${t.glowRgba}`,
          },
          success: {
            iconTheme: {
              primary: t.primary,
              secondary: "#09090b",
            },
          },
          error: {
            style: {
              border: "1px solid rgba(239, 68, 68, 0.2)",
              boxShadow: "0 0 20px rgba(239, 68, 68, 0.1)",
            },
            iconTheme: {
              primary: "#ef4444",
              secondary: "#09090b",
            },
          },
        }}
      />

      <main className="relative z-10 mx-auto flex min-h-dvh max-w-[1200px] flex-col px-3 py-4 md:px-6 md:py-16" data-service={effectiveService}>
        {/* Top Header Bar */}
        <div className="mb-4 flex w-full shrink-0 items-center justify-end gap-2 md:mb-12">
          {backendOnline === null ? (
            <span className="flex cursor-default items-center gap-1.5 rounded-full border border-[var(--clr-border)] bg-zinc-950/70 px-2.5 py-1 text-[10px] font-medium text-zinc-400 shadow-lg shadow-black/20 transition-all duration-300 hover:bg-zinc-800/80 hover:text-zinc-200">
              <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-zinc-500" />
              Backend: Connecting
            </span>
          ) : backendOnline ? (
            <span className="flex cursor-default items-center gap-1.5 rounded-full border border-emerald-900/75 bg-emerald-950/50 px-2.5 py-1 text-[10px] font-medium text-emerald-300 shadow-lg shadow-black/20 transition-all duration-300 hover:bg-emerald-900/80 hover:text-emerald-100">
              <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
              Backend: Online
            </span>
          ) : (
            <span className="flex cursor-default items-center gap-1.5 rounded-full border border-red-900/75 bg-red-950/50 px-2.5 py-1 text-[10px] font-medium text-red-300 shadow-lg shadow-black/20 transition-all duration-300 hover:bg-red-900/80 hover:text-red-100">
              <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-red-500" />
              Backend: Offline
            </span>
          )}
          <div className="group relative">
            <button
              type="button"
              className="rounded-full border border-[var(--clr-borderLight)] bg-[var(--clr-primaryBgLight)]/70 px-3 py-1 text-xs font-medium text-[var(--clr-primaryTextLight)] shadow-lg shadow-black/20 transition-colors hover:bg-[var(--clr-primaryBg)]/80"
              aria-label="Version information"
            >
              v2.2.0
            </button>
            <div className="pointer-events-none absolute right-0 top-full z-40 mt-3 w-[min(22rem,calc(100vw-1.5rem))] translate-y-1 rounded-2xl border border-[var(--clr-borderLight)] bg-[#020604]/40 p-4 text-sm text-zinc-200 opacity-0 shadow-2xl shadow-black/70 backdrop-blur-[28px] transition-all duration-200 group-focus-within:translate-y-0 group-focus-within:opacity-100 group-hover:translate-y-0 group-hover:opacity-100">
              <div className="space-y-3">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-[0.2em] text-[var(--clr-primaryTextMuted)]/90">
                    Version Roadmap
                  </p>
                  <div className="mt-2 space-y-3">
                    <p className="text-sm font-semibold text-zinc-100">To Do</p>
                    <div>
                      <p className="font-semibold text-zinc-100">v4.0.0: Spotifull Web Player</p>
                      <p className="mt-1 text-zinc-300">
                        Build Spotifull as a web player that can stream and download songs from
                        Spotify, YouTube and SoundCloud. It works the same as the Android app and
                        supports the same features, but in your browser.
                      </p>
                    </div>
                    <div>
                      <p className="font-semibold text-zinc-100">v3.0.0: Spotifull Android App</p>
                      <p className="mt-1 text-zinc-300">
                        Build Spotifull as an Android app that can stream and download tracks from
                        Spotify, YouTube, and SoundCloud, with custom profiles, imported Spotify
                        profiles, and saved playlist URLs.
                      </p>
                    </div>
                  </div>
                </div>
                <div className="h-px bg-white/70" />
                <div>
                  <p className="text-sm font-semibold text-zinc-100">History</p>
                  <div className="mt-2 space-y-3">
                    <div>
                      <p className="font-semibold text-zinc-100">v2.2.0: Multi-Source Downloads</p>
                      <p className="mt-1 text-zinc-300">
                        Download songs and playlists from Spotify, YouTube, and SoundCloud with
                        auto-detection and per-service streaming.
                      </p>
                    </div>
                    <div>
                      <p className="font-semibold text-zinc-100">v2.1.0: YouTube Source Review</p>
                      <p className="mt-1 text-zinc-300">
                        Added in-browser track previewing and YouTube URL override per track, so you
                        can fix wrong matches before downloading.
                      </p>
                    </div>
                    <div>
                      <p className="font-semibold text-zinc-100">v2.0.0: Updated UI</p>
                      <p className="mt-1 text-zinc-300">
                        Refreshed the UI and added song selection and cancellation controls.
                      </p>
                    </div>
                    <div>
                      <p className="font-semibold text-zinc-100">
                        v1.0.0: Spotify Playlist Downloads
                      </p>
                      <p className="mt-1 text-zinc-300">
                        Introduced Spotify URL processing for songs and playlists.
                      </p>
                    </div>
                    <div>
                      <p className="font-semibold text-zinc-100">base: Sunnify Fork</p>
                      <p className="mt-1 text-zinc-300">
                        Forked from sunnypattel/sunnify-spotify-downloader.
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Header / Input Section */}
        <div
          className={`relative flex flex-col items-center justify-center transition-all duration-700 ease-in-out ${tracks.length > 0 ? "mb-8 md:mb-12" : "pb-12 md:pb-24"}`}
        >
          <div className="mb-8 space-y-4 text-center md:mb-10">
            <div className="mb-2 inline-flex cursor-default items-center gap-2 rounded-full border border-emerald-900/70 bg-emerald-950/70 px-3 py-1 text-xs font-medium text-emerald-200 shadow-lg shadow-black/20 transition-all duration-300 hover:bg-emerald-900/80 hover:text-emerald-100">
              <Sparkles className="h-3 w-3 text-emerald-400" />
              <span>Spotifull Playlist Downloader</span>
            </div>
            <h1 className="pb-2 text-3xl font-bold leading-[1.1] tracking-tighter text-zinc-100 md:text-6xl md:leading-tight">
              Download any playlist.
            </h1>
            <p className="mx-auto max-w-lg px-2 text-base text-zinc-400 md:text-lg">
              Paste a Spotify, YouTube, or SoundCloud link below and download high-quality MP3s
              instantly.
            </p>
          </div>

          <div className="group relative z-30 w-full max-w-2xl">
            <div className={`absolute -inset-0.5 rounded-[2rem] ${serviceTheme[effectiveService]?.glow || "bg-[var(--clr-primaryBgLight)]"} opacity-0 blur transition duration-500 group-hover:opacity-100`}></div>
            <div className="relative flex flex-col items-center rounded-3xl border border-[var(--clr-borderLight)] bg-[#0a1410]/95 p-2 shadow-2xl shadow-black/30 backdrop-blur-xl sm:flex-row">
              <div className="flex w-full items-center py-1 pl-2 pr-2">
                <div className="relative shrink-0" ref={serviceDropdownRef}>
                  <button
                    type="button"
                    onClick={() => setShowServiceDropdown(!showServiceDropdown)}
                    className="flex items-center gap-1.5 rounded-lg px-1.5 py-1.5 text-xs font-medium text-zinc-400 transition-colors hover:bg-zinc-800/60 hover:text-zinc-200"
                  >
                    <span className="shrink-0">{serviceIcons[effectiveService]}</span>
                    <ChevronDown className="h-4 w-4 opacity-60" />
                  </button>
                  {showServiceDropdown && (
                    <div className="absolute left-0 top-full z-[9999] mt-1 w-40 rounded-xl border border-[var(--clr-border)] bg-[#0a1410] p-1 shadow-2xl shadow-black/40">
                      <div className="px-3 py-2 text-xs font-medium italic text-zinc-500">
                        Auto-detect
                      </div>
                      <div className="mx-2 my-1 border-t border-[var(--clr-border)]" />
                      {["spotify", "youtube", "soundcloud"].map((key) => {
                        const locked = playlistLink.length > 0
                        return (
                          <button
                            key={key}
                            type="button"
                            disabled={locked}
                            onClick={() => {
                              if (selectedService === key && selectedService !== "auto") {
                                setSelectedService("auto")
                              } else {
                                setSelectedService(key)
                              }
                              setShowServiceDropdown(false)
                            }}
                            className={`flex w-full items-center gap-2 rounded-lg px-3 py-2 text-xs font-medium transition-colors ${
                              locked
                                ? "cursor-not-allowed opacity-40"
                                : effectiveService === key
                                  ? "bg-zinc-800/60 text-zinc-200"
                                  : "text-zinc-400 hover:bg-zinc-800/40 hover:text-zinc-300"
                            }`}
                          >
                            <span className="shrink-0 text-base">{serviceIcons[key]}</span>
                            <span>{serviceLabels[key]}</span>
                          </button>
                        )
                      })}
                    </div>
                  )}
                </div>
                <Search className="h-5 w-5 shrink-0 text-[var(--clr-primary)]" />
                <input
                  type="text"
                  placeholder="https://open.spotify.com/playlist/..."
                  value={playlistLink}
                  onChange={(e) => {
                    const val = e.target.value
                    setPlaylistLink(val)
                    setShowServiceDropdown(false)
                    const detected = detectServiceFromUrl(val)
                    if (detected && selectedService !== "auto" && detected !== selectedService) {
                      setSelectedService("auto")
                    }
                  }}
                  onKeyDown={(e) => e.key === "Enter" && !isProcessing && handleProcess()}
                  className="w-full flex-1 border-none bg-transparent px-3 py-3 text-sm text-zinc-100 outline-none placeholder:text-zinc-600 focus:ring-0 md:text-base"
                />
                {playlistLink && (
                  <button
                    type="button"
                    onClick={() => setPlaylistLink("")}
                    className="mr-1 shrink-0 rounded-lg p-1.5 text-zinc-500 transition-colors hover:bg-zinc-800/60 hover:text-zinc-300"
                    aria-label="Clear URL"
                  >
                    <X className="h-4 w-4" />
                  </button>
                )}
              </div>
              <button
                onClick={handleProcess}
                disabled={isProcessing || backendOnline === false}
                className={`flex w-full shrink-0 items-center justify-center gap-2 rounded-2xl px-6 py-3.5 font-semibold transition-all duration-300 active:scale-95 disabled:opacity-70 disabled:hover:scale-100 sm:w-auto md:px-8 md:py-4 md:hover:scale-105 ${
                  backendOnline === false
                    ? "cursor-not-allowed border border-red-900/50 bg-red-900/30 text-red-300"
                    : serviceTheme[effectiveService]?.btn || "border border-[var(--clr-primaryDark)] bg-[var(--clr-primaryBg)]/80 text-[var(--clr-primaryText)] shadow-[0_0_20px_var(--clr-glowRgba)] hover:bg-[var(--clr-primaryDark)]/85"
                }`}
              >
                {isProcessing ? (
                  <Loader2 className="h-5 w-5 animate-spin" />
                ) : backendOnline === false ? (
                  <>
                    <span className="h-2 w-2 shrink-0 animate-pulse rounded-full bg-red-500" />
                    <span className="font-bold">Offline</span>
                  </>
                ) : (
                  <>
                    <Download className="h-5 w-5" />
                    <span className="font-bold">Fetch</span>
                  </>
                )}
              </button>
            </div>
          </div>

          {/* Progress Indicator */}
            {(isProcessing || (downloadProgress > 0 && tracks.length === 0)) && (
            <div className="relative z-0 mt-8 w-full max-w-2xl rounded-2xl border border-[var(--clr-borderSubtle)] bg-[#0a1410]/70 p-4 backdrop-blur-md md:p-6">
              <div className="mb-3 flex justify-between text-sm font-medium text-zinc-400">
                <span>{statusMessage}</span>
                {totalSongs > 0 && (
                  <span className="text-zinc-300">
                    {songsDownloaded} / {totalSongs}
                  </span>
                )}
              </div>
              {isProcessing ? (
                <div className="h-3 overflow-hidden rounded-full bg-[var(--clr-progressBg)]">
                  <div className="h-full w-full animate-pulse rounded-full bg-[var(--clr-progressBar)]" />
                </div>
              ) : (
                <Progress value={downloadProgress} className={progressBarClassName} />
              )}
            </div>
          )}
        </div>

        {/* Content Area */}
        {tracks.length > 0 && (
          <div className="grid grid-cols-1 items-start gap-4 duration-700 animate-in fade-in slide-in-from-bottom-8 md:gap-6 lg:grid-cols-[1fr_360px]">
            {/* Track List */}
            <div className="relative z-0 flex h-[60vh] flex-col overflow-hidden rounded-[2rem] border border-[var(--clr-borderSubtle)] bg-[#09120d]/80 shadow-2xl shadow-black/30 backdrop-blur-xl md:h-[700px]">
              <div className="group/header border-b border-[var(--clr-borderSubtle)] bg-[#08110c]/85 p-4 md:p-8">
                <div className="flex flex-col items-start justify-between gap-4 sm:flex-row sm:items-center">
                  <div className="flex min-w-0 items-center gap-3">
                    <div
                      className={`shrink-0 overflow-hidden transition-all duration-200 ${allTracksSelected ? "w-8 opacity-100 md:w-0 md:group-hover/header:w-8 md:group-hover/header:opacity-100" : "w-8 opacity-100"}`}
                    >
                      <button
                        type="button"
                        onClick={toggleAllTrackSelection}
                        disabled={isDownloadingAll}
                        className={`flex h-7 w-7 items-center justify-center rounded-lg border transition-all duration-200 disabled:opacity-50 ${
                          allTracksSelected
                            ? "border-[var(--clr-primaryDark)] bg-[var(--clr-primaryBgLight)]/80 text-[var(--clr-primaryTextLight)]"
                            : "border-[var(--clr-border)] bg-transparent text-zinc-500 hover:border-[var(--clr-primaryDark)] hover:text-[var(--clr-primaryTextLight)]"
                        }`}
                        aria-label={allTracksSelected ? "Deselect all songs" : "Select all songs"}
                      >
                        {allTracksSelected ? <Check className="h-4 w-4 stroke-[3]" /> : null}
                      </button>
                    </div>
                    <div className="min-w-0">
                      <h2 className="truncate text-xl font-bold tracking-tight text-zinc-100 md:text-2xl">
                        {playlistName || "Track List"}
                      </h2>
                      <p className="mt-1 text-sm text-zinc-400">
                        {tracks.length} tracks found in this playlist
                      </p>
                    </div>
                  </div>
                  <div className="flex w-full flex-col gap-2 sm:w-auto sm:flex-row">
                    <button
                      onClick={isDownloadingAll ? cancelPlaylistDownload : downloadAll}
                      disabled={!isDownloadingAll && selectedDownloadTracks.length === 0}
                      className={`flex w-full items-center justify-center gap-2 rounded-xl border px-5 py-3 text-sm font-semibold transition-all duration-300 hover:scale-[1.02] disabled:opacity-50 disabled:hover:scale-100 sm:w-auto ${
                        isDownloadingAll
                          ? "border-red-900/70 bg-red-950/70 text-red-200 shadow-[0_0_20px_rgba(127,29,29,0.2)] hover:border-red-700/80 hover:bg-red-900/80"
                          : "border-[var(--clr-borderLight)] bg-[var(--clr-primaryBgLight)]/70 text-[var(--clr-primaryTextLight)] shadow-[0_0_20px_var(--clr-shadowRgba)] hover:border-[var(--clr-primaryDark)] hover:bg-[var(--clr-primaryBg)]/80"
                      }`}
                    >
                      {isDownloadingAll ? (
                        <Square className="h-4 w-4 fill-current" />
                      ) : (
                        <Download className="h-4 w-4" />
                      )}
                      {isDownloadingAll ? "Cancel ZIP" : "ZIP"}
                    </button>
                  </div>
                </div>
                {isDownloadingAll && (
                  <div className="mt-4">
                    <div className="mb-2 flex items-center justify-between text-xs font-semibold text-zinc-400">
                      <span>ZIP Download Progress</span>
                      <span className="text-[var(--clr-primaryTextMuted)]">
                        {Math.round(playlistDownloadProgress)}%
                      </span>
                    </div>
                    <Progress value={playlistDownloadProgress} className={progressBarClassName} />
                  </div>
                )}
              </div>

              <ScrollArea className="w-full flex-1">
                <div className="space-y-1 p-2 md:p-4">
                  {tracks.map((track, idx) => (
                    <div
                      key={track.id}
                      onClick={() => setSelectedTrack(track)}
                      className={`group relative flex cursor-pointer items-center gap-3 rounded-2xl border border-transparent p-3 transition-all duration-200 md:gap-4 md:p-4 ${selectedTrack?.id === track.id ? "border-[var(--clr-border)] bg-[var(--clr-primaryBgLight)]/45 shadow-[0_0_15px_var(--clr-shadowRgba)]" : "hover:border-[var(--clr-borderSubtle)] hover:bg-[#0d1913]"}`}
                    >
                      <div className="ml-auto flex shrink-0 items-center">
                        <div
                          className={`mr-2 shrink-0 overflow-hidden transition-all duration-200 ${allTracksSelected ? "w-9 opacity-100 md:w-0 md:group-hover:w-9 md:group-hover:opacity-100" : "w-9 opacity-100"}`}
                        >
                          <button
                            onClick={(e) => {
                              e.stopPropagation()
                              toggleTrackSelection(track.id)
                            }}
                            className={`flex h-8 w-8 items-center justify-center rounded-lg border transition-all duration-200 ${
                              selectedTrackIds.includes(track.id)
                                ? "border-[var(--clr-primaryDark)] bg-[var(--clr-primaryBgLight)]/80 text-[var(--clr-primaryTextLight)]"
                                : "border-[var(--clr-border)] bg-zinc-900/70 text-zinc-500 hover:border-[var(--clr-primaryDark)] hover:text-[var(--clr-primaryTextLight)]"
                            }`}
                            aria-label={
                              selectedTrackIds.includes(track.id) ? "Deselect song" : "Select song"
                            }
                          >
                            {selectedTrackIds.includes(track.id) ? (
                              <Check className="h-4 w-4 stroke-[3]" />
                            ) : null}
                          </button>
                        </div>
                        <span
                          className={`w-5 text-center text-xs font-medium md:w-6 md:text-sm ${selectedTrack?.id === track.id ? "text-[var(--clr-primaryTextMuted)]" : "text-zinc-500 group-hover:text-zinc-400"}`}
                        >
                          {idx + 1}
                        </span>
                      </div>

                      {(urlMeta[track.id]?.thumbnail || track.cover) ? (
                        <div className="relative h-11 w-11 shrink-0 overflow-hidden rounded-xl shadow-md transition-transform duration-200 group-hover:translate-x-1 md:h-14 md:w-14">
                          <Image
                            src={urlMeta[track.id]?.thumbnail || track.cover}
                            alt=""
                            fill
                            className="object-cover"
                            unoptimized
                          />
                          {streamingTrackId === track.id && isPlaying && (
                            <div className="absolute inset-0 flex items-center justify-center gap-1 bg-black/35">
                              <div
                                className="animate-smooth-bounce h-5 w-1.5 rounded-full bg-[var(--clr-primary)]"
                                style={{ animationDelay: "0ms" }}
                              />
                              <div
                                className="animate-smooth-bounce h-7 w-1.5 rounded-full bg-[var(--clr-primary)]"
                                style={{ animationDelay: "150ms" }}
                              />
                              <div
                                className="animate-smooth-bounce h-4 w-1.5 rounded-full bg-[var(--clr-primary)]"
                                style={{ animationDelay: "300ms" }}
                              />
                            </div>
                          )}
                        </div>
                      ) : (
                        <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-zinc-900 transition-transform duration-200 group-hover:translate-x-1 md:h-14 md:w-14">
                          <Music2 className="h-5 w-5 text-zinc-500 md:h-6 md:w-6" />
                        </div>
                      )}

                      <div className="min-w-0 flex-1 pr-3 transition-transform duration-200 group-hover:translate-x-1 md:pr-4">
                        <h3
                          className={`truncate text-sm font-semibold md:text-base ${selectedTrack?.id === track.id ? "text-white" : "text-zinc-200"}`}
                        >
                          {track.title}
                        </h3>
                        <p className="mt-0.5 truncate text-xs text-zinc-400 md:text-sm">
                          {track.album}
                        </p>
                      </div>

                      <div className="flex shrink-0 items-center">
                        {trackProgress[track.id] !== undefined ? (
                          trackProgress[track.id] === -1 ? (
                            <span className="rounded-lg border border-red-900/50 bg-red-950/40 px-3 py-1.5 text-xs font-medium text-red-300">
                              Error
                            </span>
                          ) : (
                            <div className="flex items-center gap-2">
                              <span className="shrink-0 text-xs font-bold tracking-wider text-[var(--clr-primaryTextMuted)] md:text-sm">
                                {Math.round(trackProgress[track.id])}%
                              </span>
                              {isDownloadingTrack === track.id ? (
                                <button
                                  onClick={(e) => {
                                    e.stopPropagation()
                                    void cancelTrackDownload(track.id)
                                  }}
                                  className="flex shrink-0 transform items-center justify-center rounded-xl border border-red-900/70 bg-red-950/70 p-2.5 text-red-200 transition-all duration-300 hover:scale-110 hover:border-red-700/80 hover:bg-red-900/80 hover:text-white hover:shadow-[0_0_16px_rgba(127,29,29,0.35)] active:scale-90"
                                  aria-label="Stop download"
                                >
                                  <Square className="h-5 w-5 fill-current" />
                                </button>
                              ) : trackProgress[track.id] >= 100 ? (
                                <button
                                  onClick={(e) => {
                                    e.stopPropagation()
                                    downloadTrack(track)
                                  }}
                                  className="flex shrink-0 transform items-center justify-center rounded-xl border border-[var(--clr-primaryBg)] bg-[var(--clr-primaryBgLight)]/30 p-2.5 text-[var(--clr-primaryTextMuted)] transition-all duration-300 hover:-translate-y-0.5 hover:scale-110 hover:border-[var(--clr-primaryDark)] hover:bg-[var(--clr-primaryBgLight)]/45 hover:text-[var(--clr-primaryTextLight)] hover:shadow-[0_0_15px_var(--clr-glowRgba)] active:scale-90"
                                  aria-label="Download track"
                                >
                                  <Download className="h-5 w-5" />
                                </button>
                              ) : null}
                            </div>
                          )
                        ) : isDownloadingTrack === track.id ? (
                          <button
                            onClick={(e) => {
                              e.stopPropagation()
                              void cancelTrackDownload(track.id)
                            }}
                            className="flex transform items-center justify-center rounded-xl border border-red-900/70 bg-red-950/70 p-2.5 text-red-200 transition-all duration-300 hover:scale-110 hover:border-red-700/80 hover:bg-red-900/80 hover:text-white hover:shadow-[0_0_16px_rgba(127,29,29,0.35)] active:scale-90"
                            aria-label="Stop download"
                          >
                            <Square className="h-5 w-5 fill-current" />
                          </button>
                        ) : (
                          <button
                            onClick={(e) => {
                              e.stopPropagation()
                              downloadTrack(track)
                            }}
                            className="flex transform items-center justify-center rounded-xl border border-[var(--clr-primaryBg)] bg-[var(--clr-primaryBgLight)]/30 p-2.5 text-[var(--clr-primaryTextMuted)] opacity-100 transition-all duration-300 hover:-translate-y-0.5 hover:scale-110 hover:border-[var(--clr-primaryDark)] hover:bg-[var(--clr-primaryBgLight)]/45 hover:text-[var(--clr-primaryTextLight)] hover:shadow-[0_0_15px_var(--clr-glowRgba)] focus:opacity-100 active:scale-90"
                            aria-label="Download track"
                          >
                            <Download className="h-5 w-5" />
                          </button>
                        )}
                      </div>
                      {trackProgress[track.id] !== undefined && trackProgress[track.id] !== -1 ? (
                        <div className="absolute inset-x-3 bottom-0 h-px overflow-hidden rounded-full bg-[var(--clr-primaryBgLight)]/70 md:inset-x-4">
                          <div
                            className="h-full bg-[var(--clr-primary)] shadow-[0_0_12px_var(--clr-glowRgba)] transition-[width] duration-300"
                            style={{
                              width: `${Math.max(0, Math.min(100, trackProgress[track.id]))}%`,
                            }}
                          />
                        </div>
                      ) : null}
                    </div>
                  ))}
                </div>
              </ScrollArea>
            </div>

            {/* Now Playing / Selection */}
            <div className="md:sticky md:top-6">
              {selectedTrack ? (
                <div className="flex flex-col items-center rounded-[2rem] border border-[var(--clr-borderSubtle)] bg-[#09120d]/80 p-5 text-center shadow-2xl shadow-black/30 backdrop-blur-xl duration-300 animate-in fade-in zoom-in-95 md:p-8">
                  <div className="group relative mb-8 aspect-square w-full overflow-hidden rounded-2xl shadow-2xl">
                    {(urlMeta[selectedTrack.id]?.thumbnail || selectedTrack.cover) ? (
                      <Image
                        src={urlMeta[selectedTrack.id]?.thumbnail || selectedTrack.cover}
                        alt=""
                        fill
                        className="object-cover transition-transform duration-700 group-hover:scale-105"
                        unoptimized
                      />
                    ) : (
                      <div className="flex h-full w-full items-center justify-center bg-zinc-900">
                        <Music2 className="h-20 w-20 text-zinc-600" />
                      </div>
                    )}
                    <div className="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent opacity-0 transition-opacity duration-300 group-hover:opacity-100" />
                  </div>

                  <h3 className="mb-2 px-2 text-2xl font-bold leading-tight text-white">
                    {selectedTrack.title}
                  </h3>
                  <p className={`text-base font-medium ${selectedTrack.album ? 'mb-0.5' : 'mb-8'} text-zinc-400`}>
                    {selectedTrack.artists}
                  </p>
                  {selectedTrack.album && (
                    <p className="mb-8 text-sm font-medium text-zinc-500">
                      {selectedTrack.album}
                    </p>
                  )}

                  <div className="w-full space-y-3">
                    {/* Stream / Preview Player */}
                    <div className="w-full space-y-3 rounded-2xl border border-[var(--clr-border)] bg-[var(--clr-primaryBgLight)]/20 p-4">
                      <div className="flex items-center gap-3">
                        <button
                          id={`stream-btn-${selectedTrack.id}`}
                          onClick={() => toggleStream(selectedTrack)}
                          disabled={isLoadingStream && streamingTrackId !== selectedTrack.id}
                          className={`flex items-center gap-1.5 rounded-xl border px-3 py-2.5 text-sm font-semibold transition-all duration-300 hover:scale-105 active:scale-95 disabled:opacity-50 disabled:hover:scale-100 ${
                            streamingTrackId === selectedTrack.id
                              ? "border-[var(--clr-primaryDark)] bg-[var(--clr-primaryBg)]/70 text-[var(--clr-primaryTextLight)] hover:bg-[var(--clr-primaryDark)]/80"
                              : "border-[var(--clr-border)] bg-[var(--clr-primaryBgLight)]/20 text-zinc-300 hover:bg-zinc-800/80 hover:text-white"
                          }`}
                          aria-label={
                            streamingTrackId === selectedTrack.id && isPlaying
                              ? "Pause preview"
                              : "Play preview"
                          }
                        >
                          {isLoadingStream && streamingTrackId === selectedTrack.id ? (
                            <Loader2 className="h-4 w-4 animate-spin" />
                          ) : streamingTrackId === selectedTrack.id && isPlaying ? (
                            <Pause className="h-4 w-4 fill-current" />
                          ) : (
                            <Play className="h-4 w-4 fill-current" />
                          )}
                          <span>
                            {isLoadingStream && streamingTrackId === selectedTrack.id
                              ? "Loading…"
                              : streamingTrackId === selectedTrack.id && isPlaying
                                ? "Pause"
                                : streamingTrackId === selectedTrack.id
                                  ? "Resume"
                                  : "Preview"}
                          </span>
                          <Radio className="h-3.5 w-3.5 opacity-60" />
                        </button>
                        {streamingTrackId === selectedTrack.id && (
                          <button
                            onClick={stopStream}
                            className="rounded-xl border border-[var(--clr-border)] bg-zinc-900/50 p-2 text-zinc-400 transition-all duration-200 hover:bg-zinc-800/70 hover:text-white"
                            aria-label="Stop preview"
                          >
                            <Square className="h-3.5 w-3.5 fill-current" />
                          </button>
                        )}
                        <span className="ml-auto shrink-0 whitespace-nowrap font-mono text-xs tabular-nums text-zinc-500">
                          {streamingTrackId === selectedTrack.id && streamDuration > 0
                            ? `${Math.floor((streamProgress * streamDuration) / 60)
                                .toString()
                                .padStart(2, "0")}:${Math.floor(
                                (streamProgress * streamDuration) % 60
                              )
                                .toString()
                                .padStart(2, "0")} / ${Math.floor(streamDuration / 60)
                                .toString()
                                .padStart(2, "0")}:${Math.floor(streamDuration % 60)
                                .toString()
                                .padStart(2, "0")}`
                            : ""}
                        </span>
                      </div>
                      {streamingTrackId === selectedTrack.id && (
                        <div
                          className="relative h-1.5 w-full cursor-pointer overflow-hidden rounded-full bg-zinc-800"
                          onClick={(e) => {
                            const rect = e.currentTarget.getBoundingClientRect()
                            seekStream((e.clientX - rect.left) / rect.width)
                          }}
                          role="slider"
                          aria-valuenow={Math.round(streamProgress * 100)}
                          aria-valuemin={0}
                          aria-valuemax={100}
                          aria-label="Playback position"
                        >
                          <div
                            className="h-full rounded-full bg-[var(--clr-primary)] shadow-[0_0_8px_var(--clr-glowRgba)] transition-[width] duration-200"
                            style={{ width: `${streamProgress * 100}%` }}
                          />
                        </div>
                      )}
                    </div>

                    {/* Source URL Section */}
                    <div className="w-full space-y-3 rounded-2xl border border-[var(--clr-border)] bg-zinc-900/30 p-4">
                      <div className="flex items-center justify-between">
                        <p className="text-xs font-semibold uppercase tracking-wider text-zinc-500">
                          Audio Source
                        </p>
                        <div className="flex items-center gap-1.5">
                          {urlOverrides[selectedTrack.id] && (
                            <button
                              onClick={() => resetUrl(selectedTrack.id)}
                              className="rounded-lg p-1.5 text-zinc-500 transition-all duration-200 hover:bg-zinc-800/60 hover:text-zinc-300"
                              title="Reset to auto-detected source"
                              aria-label="Reset source"
                            >
                              <RotateCcw className="h-3.5 w-3.5" />
                            </button>
                          )}
                          {!isEditingUrl ? (
                            <button
                              onClick={() => startEditingUrl(selectedTrack)}
                              className="rounded-lg p-1.5 text-zinc-500 transition-all duration-200 hover:bg-[var(--clr-primaryBgLight)]/40 hover:text-[var(--clr-primaryLight)]"
                              title="Edit source URL"
                              aria-label="Edit source URL"
                            >
                              <Pencil className="h-3.5 w-3.5" />
                            </button>
                          ) : (
                            <button
                              onClick={cancelEditingUrl}
                              className="rounded-lg p-1.5 text-zinc-500 transition-all duration-200 hover:bg-zinc-800/60 hover:text-zinc-300"
                              aria-label="Cancel editing"
                            >
                              <X className="h-3.5 w-3.5" />
                            </button>
                          )}
                        </div>
                      </div>

                      {isEditingUrl ? (
                        <div className="space-y-2">
                          <input
                            id={`url-input-${selectedTrack.id}`}
                            type="url"
                            placeholder="https://www.youtube.com/watch?v=..."
                            value={urlDraft}
                            onChange={(e) => setUrlDraft(e.target.value)}
                            onKeyDown={(e) => {
                              if (e.key === "Enter") saveUrl(selectedTrack)
                              if (e.key === "Escape") cancelEditingUrl()
                            }}
                            className="w-full rounded-xl border border-[var(--clr-border)] bg-zinc-900/80 px-3 py-2 text-xs text-zinc-200 outline-none transition-all placeholder:text-zinc-600 focus:border-[var(--clr-primaryDark)] focus:ring-1 focus:ring-[var(--clr-primaryBg)]/50"
                            autoFocus
                          />
                          <button
                            onClick={() => saveUrl(selectedTrack)}
                            disabled={isResolvingUrl}
                            className="flex w-full items-center justify-center gap-2 rounded-xl border border-[var(--clr-primaryDark)] bg-[var(--clr-primaryBg)]/70 py-2 text-xs font-semibold text-[var(--clr-primaryTextLight)] transition-all duration-200 hover:scale-[1.02] hover:bg-[var(--clr-primaryDark)]/80 disabled:opacity-60"
                          >
                            {isResolvingUrl ? (
                              <Loader2 className="h-3.5 w-3.5 animate-spin" />
                            ) : (
                              <Check className="h-3.5 w-3.5" />
                            )}
                            {isResolvingUrl ? "Resolving…" : "Save URL"}
                          </button>
                        </div>
                      ) : urlMeta[selectedTrack.id] ? (
                        <div className="flex items-center gap-3">
                          {urlMeta[selectedTrack.id]!.thumbnail && (
                            <div className="relative h-10 w-14 shrink-0 overflow-hidden rounded-lg border border-[var(--clr-border)]">
                              <Image
                                src={urlMeta[selectedTrack.id]!.thumbnail}
                                alt=""
                                fill
                                className="object-cover"
                                unoptimized
                              />
                            </div>
                          )}
                          <div className="min-w-0 flex-1">
                            <p className="truncate text-xs font-medium text-zinc-200">
                              {urlMeta[selectedTrack.id]!.title}
                            </p>
                            <p className="truncate text-[11px] text-zinc-500">
                              {urlMeta[selectedTrack.id]!.channel}
                            </p>
                          </div>
                          <a
                            href={urlOverrides[selectedTrack.id]}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="shrink-0 rounded-lg p-1.5 text-zinc-500 transition-all duration-200 hover:bg-zinc-800/60 hover:text-zinc-200"
                            aria-label="Open source"
                          >
                            <ExternalLink className="h-3.5 w-3.5" />
                          </a>
                        </div>
                      ) : (
                        <div className="space-y-2">
                          {urlOverrides[selectedTrack.id] || selectedTrack.sourceUrl ? (
                            <>
                              <a
                                href={urlOverrides[selectedTrack.id] || selectedTrack.sourceUrl!}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="flex min-w-0 items-center gap-1.5 text-xs text-zinc-400 transition-colors hover:text-[var(--clr-primaryLight)]"
                              >
                                <ExternalLink className="h-3 w-3 shrink-0" />
                                <span className="truncate">
                                  {urlOverrides[selectedTrack.id]
                                    ? urlOverrides[selectedTrack.id]
                                    : selectedTrack.sourceUrl}
                                </span>
                              </a>
                              <a
                                href={urlOverrides[selectedTrack.id] || selectedTrack.sourceUrl!}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="group/embed relative block aspect-video w-full overflow-hidden rounded-lg border border-[var(--clr-border)]"
                              >
                                {selectedTrack.cover ? (
                                  <Image
                                    src={selectedTrack.cover}
                                    alt=""
                                    fill
                                    className="object-cover transition-transform duration-300 group-hover/embed:scale-105"
                                    unoptimized
                                  />
                                ) : (
                                  <div className="flex h-full w-full items-center justify-center bg-zinc-900">
                                    <Music2 className="h-6 w-6 text-zinc-600" />
                                  </div>
                                )}
                                <div className="absolute inset-0 flex items-center justify-center bg-black/20 transition-colors group-hover/embed:bg-black/40">
                                  <div className="flex h-10 w-10 items-center justify-center rounded-full bg-black/60 transition-transform group-hover/embed:scale-110">
                                    <Play className="ml-0.5 h-5 w-5 fill-white text-white" />
                                  </div>
                                </div>
                              </a>
                            </>
                          ) : null}
                        </div>
                      )}
                    </div>

                    <button
                      onClick={() => {
                        if (isDownloadingTrack === selectedTrack.id)
                          void cancelTrackDownload(selectedTrack.id)
                        else downloadTrack(selectedTrack)
                      }}
                      className={`w-full rounded-2xl py-4 ${isDownloadingTrack === selectedTrack.id ? "border border-red-900/50 bg-red-950/35 text-red-300 hover:bg-red-950/55" : serviceTheme[effectiveService]?.btn || "border border-[var(--clr-primary)] bg-[var(--clr-primaryBg)] text-[var(--clr-primaryText)] hover:bg-[var(--clr-primaryDark)]"} flex items-center justify-center gap-2 font-bold transition-all duration-300 active:scale-95 disabled:opacity-70 disabled:hover:scale-100 md:hover:scale-105`}
                    >
                      {isDownloadingTrack === selectedTrack.id ? (
                        <>
                          <Square className="h-5 w-5 fill-current" />
                          Cancel Download
                        </>
                      ) : (
                        <>
                          <Download className="h-5 w-5" />
                          Download MP3
                        </>
                      )}
                    </button>

                  </div>
                </div>
              ) : (
                <div className="flex h-[500px] flex-col items-center justify-center rounded-[2rem] border border-dashed border-[var(--clr-borderSubtle)] bg-[#09120d]/55 p-8 text-center">
                  <div className="mb-6 flex h-20 w-20 items-center justify-center rounded-full bg-zinc-900/70">
                    <Music2 className="h-10 w-10 text-zinc-600" />
                  </div>
                  <h3 className="mb-2 text-lg font-semibold text-zinc-300">No track selected</h3>
                  <p className="max-w-[200px] font-medium text-zinc-500">
                    Select a track from the list to view details and download.
                  </p>
                </div>
              )}
            </div>
          </div>
        )}
      </main>
    </div>
  )
}
