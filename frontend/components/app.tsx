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
  Radio
} from "lucide-react"
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
  youtubeUrl?: string
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

  // YouTube URL override state
  const [youtubeUrls, setYoutubeUrls] = useState<Record<string, string>>({})
  const [isEditingYtUrl, setIsEditingYtUrl] = useState(false)
  const [ytUrlDraft, setYtUrlDraft] = useState("")
  const [isResolvingYtUrl, setIsResolvingYtUrl] = useState(false)
  const [ytUrlMeta, setYtUrlMeta] = useState<Record<string, { title: string; channel: string; thumbnail: string; duration: number } | null>>({})

  // Streaming state
  const [streamingTrackId, setStreamingTrackId] = useState<string | null>(null)
  const [isLoadingStream, setIsLoadingStream] = useState(false)
  const [isPlaying, setIsPlaying] = useState(false)
  const [streamProgress, setStreamProgress] = useState(0) // 0-1
  const [streamDuration, setStreamDuration] = useState(0)
  const audioRef = useRef<HTMLAudioElement | null>(null)

  const progressBarClassName = "h-3 bg-[#0f1f16] [&>div]:bg-emerald-700 rounded-full"
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

  const startEditingYtUrl = (track: Track) => {
    setYtUrlDraft(youtubeUrls[track.id] || "")
    setIsEditingYtUrl(true)
  }

  const cancelEditingYtUrl = () => {
    setIsEditingYtUrl(false)
    setYtUrlDraft("")
  }

  const resetYtUrl = (trackId: string) => {
    setYoutubeUrls((prev) => { const n = { ...prev }; delete n[trackId]; return n })
    setYtUrlMeta((prev) => { const n = { ...prev }; delete n[trackId]; return n })
    setIsEditingYtUrl(false)
    setYtUrlDraft("")
    toast.success("Reset to auto-detected YouTube source")
  }

  const saveYtUrl = async (track: Track) => {
    const url = ytUrlDraft.trim()
    if (!url) {
      cancelEditingYtUrl()
      return
    }
    if (!(url.includes("youtube.com") || url.includes("youtu.be"))) {
      toast.error("Please enter a valid YouTube URL")
      return
    }
    setIsResolvingYtUrl(true)
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
      setYoutubeUrls((prev) => ({ ...prev, [track.id]: url }))
      setYtUrlMeta((prev) => ({ ...prev, [track.id]: meta }))
      setIsEditingYtUrl(false)
      setYtUrlDraft("")
      toast.success("YouTube source updated")
    } catch (err: any) {
      toast.error(err.message || "Failed to resolve YouTube URL")
    } finally {
      setIsResolvingYtUrl(false)
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
      const youtubeUrl = youtubeUrls[track.id] || ""
      const params = new URLSearchParams()
      if (youtubeUrl) {
        params.set("youtube_url", youtubeUrl)
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
      audio.onended = () => { setIsPlaying(false); setStreamProgress(1) }
      audio.onerror = () => { toast.error("Stream error"); stopStream() }
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
    return () => { stopStream() }
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
        } catch (e) { }
      }, 500)

      const youtubeUrl = youtubeUrls[track.id] || ""
      const res = await fetch(`${LOCAL_API}/api/download-track`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ...track, youtubeUrl }),
        signal: controller.signal
      })

      clearTrackProgressInterval()
      setTrackProgress((prev) => ({ ...prev, [track.id]: 100 }))

      if (!res.ok) {
        const errorData = await res.json().catch(() => ({}))
        throw new Error(errorData.message || "Download failed")
      }

      const blob = await res.blob()
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
        fetch(`${LOCAL_API}/api/cancel-track/${track.id}`, { method: 'POST' }).catch(() => { })
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
        selectedDownloadTracks.forEach(track => {
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
              selectedDownloadTracks.forEach(t => {
                if (data[t.id] !== undefined) {
                  ns[t.id] = data[t.id]
                }
              })
              setPlaylistDownloadProgress(getPlaylistProgress(ns))
              return ns
            })
          }
        } catch (e) { }
      }, 1000)

      const res = await fetch(`${LOCAL_API}/api/download-playlist-zip`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          tracks: selectedDownloadTracks.map((t) => ({ ...t, youtubeUrl: youtubeUrls[t.id] || "" })),
          playlistName
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
        await fetch(`${LOCAL_API}/api/cancel-playlist/${job_id}`, { method: "POST" }).catch(() => { })
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
            signal: playlistStatusAbortRef.current?.signal
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
      toast.error("Please enter a Spotify URL")
      return
    }

    if (!playlistLink.includes("open.spotify.com")) {
      toast.error("Invalid URL - must be from open.spotify.com")
      return
    }

    setIsProcessing(true)
    setDownloadProgress(0)
    setSongsDownloaded(0)
    setTotalSongs(0)
    setStatusMessage("Fetching playlist data...")
    setTracks([])
    setSelectedTrack(null)

    try {
      const response = await fetch(
        `${LOCAL_API}/api/scrape-playlist`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ playlistUrl: playlistLink }),
        }
      )

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
        setPlaylistLink("")
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
    <div className={`min-h-dvh bg-[#07110b] text-zinc-50 font-sans selection:bg-emerald-900/40 ${tracks.length === 0 ? "h-dvh overflow-hidden" : ""}`}>
      {/* Background Gradient */}
      <div className="fixed inset-0 z-0 overflow-hidden pointer-events-none">
        <div className="absolute -top-[25%] -left-[10%] w-[80%] h-[80%] rounded-full bg-emerald-950/50 blur-[140px] mix-blend-screen" />
        <div className="absolute top-[20%] -right-[10%] w-[60%] h-[60%] rounded-full bg-green-950/35 blur-[140px] mix-blend-screen" />
      </div>

      <Toaster
        position="top-center"
        toastOptions={{
          style: {
            background: "#07110b",
            color: "#f4f4f5",
            border: "1px solid rgba(16, 185, 129, 0.18)",
            borderRadius: "1rem",
            boxShadow: "0 0 20px rgba(6, 95, 70, 0.2)",
          },
          success: {
            iconTheme: {
              primary: '#10b981',
              secondary: '#09090b',
            },
          },
          error: {
            style: {
              border: "1px solid rgba(239, 68, 68, 0.2)",
              boxShadow: "0 0 20px rgba(239, 68, 68, 0.1)",
            },
            iconTheme: {
              primary: '#ef4444',
              secondary: '#09090b',
            },
          },
        }}
      />

      <main className="relative z-10 max-w-[1200px] mx-auto px-2 py-4 md:px-4 md:py-16 flex flex-col min-h-dvh">

        {/* Top Header Bar */}
        <div className="w-full flex justify-end items-center gap-2 mb-6 md:mb-12 shrink-0">
          {backendOnline === null ? (
            <span className="flex items-center gap-1.5 rounded-full border border-zinc-800 bg-zinc-950/70 px-2.5 py-1 text-[10px] font-medium text-zinc-400 transition-all duration-300 hover:bg-zinc-800/80 hover:text-zinc-200 shadow-lg shadow-black/20 cursor-default">
              <span className="h-1.5 w-1.5 rounded-full bg-zinc-500 animate-pulse" />
              Backend: Connecting
            </span>
          ) : backendOnline ? (
            <span className="flex items-center gap-1.5 rounded-full border border-emerald-900/75 bg-emerald-950/50 px-2.5 py-1 text-[10px] font-medium text-emerald-300 transition-all duration-300 hover:bg-emerald-900/80 hover:text-emerald-100 shadow-lg shadow-black/20 cursor-default">
              <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
              Backend: Online
            </span>
          ) : (
            <span className="flex items-center gap-1.5 rounded-full border border-red-900/75 bg-red-950/50 px-2.5 py-1 text-[10px] font-medium text-red-300 transition-all duration-300 hover:bg-red-900/80 hover:text-red-100 shadow-lg shadow-black/20 cursor-default">
              <span className="h-1.5 w-1.5 rounded-full bg-red-500 animate-pulse" />
              Backend: Offline
            </span>
          )}
          <div className="group relative">
            <button
              type="button"
              className="rounded-full border border-emerald-900/70 bg-emerald-950/70 px-3 py-1 text-xs font-medium text-emerald-200 shadow-lg shadow-black/20 transition-colors hover:bg-emerald-900/80 hover:text-emerald-100"
              aria-label="Version information"
            >
              v2.1.0
            </button>
            <div className="pointer-events-none absolute right-0 top-full mt-3 w-[min(22rem,calc(100vw-1.5rem))] translate-y-1 rounded-2xl border border-emerald-900/80 bg-[#020604]/40 p-4 text-sm text-zinc-200 opacity-0 shadow-2xl shadow-black/70 backdrop-blur-[28px] transition-all duration-200 group-hover:translate-y-0 group-hover:opacity-100 group-focus-within:translate-y-0 group-focus-within:opacity-100 z-30">
              <div className="space-y-3">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-[0.2em] text-emerald-300/90">Version Roadmap</p>
                  <div className="mt-2 space-y-3">
                    <p className="text-sm font-semibold text-zinc-100">To Do</p>
                    <div>
                      <p className="font-semibold text-zinc-100">v4.0.0: Spotifull Web Player</p>
                      <p className="mt-1 text-zinc-300">Build Spotifull as a web player that can stream and download songs from Spotify, YouTube and SoundCloud. It works the same as the Android app and supports the same features, but in your browser.</p>
                    </div>
                    <div>
                      <p className="font-semibold text-zinc-100">v3.0.0: Spotifull Android App</p>
                      <p className="mt-1 text-zinc-300">Build Spotifull as an Android app that can stream and download tracks from Spotify, YouTube, and SoundCloud, with custom profiles, imported Spotify profiles, and saved playlist URLs.</p>
                    </div>
                    <div>
                      <p className="font-semibold text-zinc-100">v2.2.0: Multi-Source Downloads</p>
                      <p className="mt-1 text-zinc-300">Add support for downloading songs and playlists from Spotify, YouTube, and SoundCloud.</p>
                    </div>
                  </div>
                </div>
                <div className="h-px bg-white/70" />
                <div>
                  <p className="text-sm font-semibold text-zinc-100">History</p>
                  <div className="mt-2 space-y-3">
                    <div>
                      <p className="font-semibold text-zinc-100">v2.1.0: YouTube Source Review</p>
                      <p className="mt-1 text-zinc-300">Added in-browser track previewing and YouTube URL override per track, so you can fix wrong matches before downloading.</p>
                    </div>
                    <div>
                      <p className="font-semibold text-zinc-100">v2.0.0: Updated UI</p>
                      <p className="mt-1 text-zinc-300">Refreshed the UI and added song selection and cancellation controls.</p>
                    </div>
                    <div>
                      <p className="font-semibold text-zinc-100">v1.0.0: Spotify Playlist Downloads</p>
                      <p className="mt-1 text-zinc-300">Introduced Spotify URL processing for songs and playlists.</p>
                    </div>
                    <div>
                      <p className="font-semibold text-zinc-100">base: Sunnify Fork</p>
                      <p className="mt-1 text-zinc-300">Forked from sunnypattel/sunnify-spotify-downloader.</p>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Header / Input Section */}
        <div className={`relative transition-all duration-700 ease-in-out flex flex-col items-center justify-center ${tracks.length > 0 ? "mb-8 md:mb-12" : "flex-1 pb-12 md:pb-24"}`}>

          <div className="text-center space-y-4 mb-8 md:mb-10">
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-emerald-950/70 border border-emerald-900/70 text-xs font-medium mb-2 text-emerald-200 transition-all duration-300 hover:bg-emerald-900/80 hover:text-emerald-100 shadow-lg shadow-black/20 cursor-default">
              <Sparkles className="w-3 h-3 text-emerald-400" />
              <span>Spotifull Playlist Downloader</span>
            </div>
            <h1 className="text-4xl md:text-6xl font-bold tracking-tighter text-zinc-100 pb-2 leading-[1.05] md:leading-tight">
              Download any playlist.
            </h1>
            <p className="text-zinc-400 max-w-lg mx-auto text-base md:text-lg px-2">
              Paste your Spotify playlist or track URL below and download high-quality MP3s instantly.
            </p>
          </div>

          <div className="w-full max-w-2xl relative group">
            <div className="absolute -inset-0.5 bg-emerald-900/20 rounded-[2rem] blur opacity-0 group-hover:opacity-100 transition duration-500"></div>
            <div className="relative flex flex-col sm:flex-row items-center bg-[#0a1410]/95 backdrop-blur-xl border border-emerald-950/70 rounded-3xl p-2 shadow-2xl shadow-black/30">
              <div className="w-full flex items-center pl-4 pr-2 py-1">
                <Search className="w-5 h-5 text-emerald-600 shrink-0" />
                <input
                  type="text"
                  placeholder="https://open.spotify.com/playlist/..."
                  value={playlistLink}
                  onChange={(e) => setPlaylistLink(e.target.value)}
                  onKeyDown={(e) => e.key === "Enter" && !isProcessing && handleProcess()}
                  className="flex-1 bg-transparent border-none outline-none text-zinc-100 px-4 py-3 placeholder:text-zinc-600 focus:ring-0 w-full text-sm md:text-base"
                />
              </div>
              <button
                onClick={handleProcess}
                disabled={isProcessing || backendOnline === false}
                className={`w-full sm:w-auto px-6 py-3.5 md:px-8 md:py-4 rounded-2xl font-semibold transition-all duration-300 hover:scale-105 disabled:opacity-70 flex items-center justify-center gap-2 shrink-0 disabled:hover:scale-100 ${backendOnline === false
                  ? "bg-red-900/30 text-red-300 border border-red-900/50 cursor-not-allowed"
                  : "bg-emerald-900/80 text-emerald-50 hover:bg-emerald-800/85 border border-emerald-700/70 shadow-[0_0_20px_rgba(6,95,70,0.25)]"
                  }`}
              >
                {isProcessing ? (
                  <Loader2 className="w-5 h-5 animate-spin" />
                ) : backendOnline === false ? (
                  <>
                    <span className="h-2 w-2 rounded-full bg-red-500 animate-pulse shrink-0" />
                    <span className="font-bold">Offline</span>
                  </>
                ) : (
                  <>
                    <Download className="w-5 h-5" />
                    <span className="font-bold">Fetch</span>
                  </>
                )}
              </button>
            </div>
          </div>

          {/* Progress Indicator */}
          {(isProcessing || (downloadProgress > 0 && tracks.length === 0)) && (
            <div className="w-full max-w-2xl mt-8 p-4 md:p-6 bg-[#0a1410]/70 border border-emerald-950/60 rounded-2xl backdrop-blur-md">
              <div className="flex justify-between text-sm text-zinc-400 mb-3 font-medium">
                <span>{statusMessage}</span>
                {totalSongs > 0 && <span className="text-zinc-300">{songsDownloaded} / {totalSongs}</span>}
              </div>
              <Progress value={downloadProgress} className={progressBarClassName} />
            </div>
          )}
        </div>

        {/* Content Area */}
        {tracks.length > 0 && (
          <div className="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-4 md:gap-6 items-start animate-in fade-in slide-in-from-bottom-8 duration-700">

            {/* Track List */}
            <div className="bg-[#09120d]/80 backdrop-blur-xl border border-emerald-950/60 rounded-[2rem] overflow-hidden shadow-2xl shadow-black/30 flex flex-col h-[72vh] md:h-[700px]">
              <div className="group/header p-4 md:p-8 border-b border-emerald-950/60 bg-[#08110c]/85">
                <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
                  <div className="flex items-center gap-3 min-w-0">
                    <div className={`shrink-0 overflow-hidden transition-all duration-200 ${allTracksSelected ? "w-8 opacity-100 md:w-0 md:group-hover/header:w-8 md:group-hover/header:opacity-100" : "w-8 opacity-100"}`}>
                      <button
                        type="button"
                        onClick={toggleAllTrackSelection}
                        disabled={isDownloadingAll}
                        className={`h-7 w-7 rounded-lg border transition-all duration-200 flex items-center justify-center disabled:opacity-50 ${allTracksSelected
                          ? "bg-emerald-950/80 border-emerald-700/80 text-emerald-200"
                          : "bg-transparent border-zinc-500 text-zinc-500 hover:text-emerald-200 hover:border-emerald-800/70"
                          }`}
                        aria-label={allTracksSelected ? "Deselect all songs" : "Select all songs"}
                      >
                        {allTracksSelected ? <Check className="h-4 w-4 stroke-[3]" /> : null}
                      </button>
                    </div>
                    <div className="min-w-0">
                      <h2 className="text-xl md:text-2xl font-bold text-zinc-100 tracking-tight truncate">{playlistName || "Track List"}</h2>
                      <p className="text-sm text-zinc-400 mt-1">{tracks.length} tracks found in this playlist</p>
                    </div>
                  </div>
                  <div className="flex w-full flex-col gap-2 sm:w-auto sm:flex-row">
                    <button
                      onClick={isDownloadingAll ? cancelPlaylistDownload : downloadAll}
                      disabled={!isDownloadingAll && selectedDownloadTracks.length === 0}
                      className={`w-full sm:w-auto flex items-center justify-center gap-2 px-5 py-3 rounded-xl text-sm font-semibold transition-all duration-300 hover:scale-[1.02] disabled:opacity-50 disabled:hover:scale-100 border ${isDownloadingAll
                        ? "bg-red-950/70 hover:bg-red-900/80 text-red-200 border-red-900/70 hover:border-red-700/80 shadow-[0_0_20px_rgba(127,29,29,0.2)]"
                        : "bg-emerald-950/70 hover:bg-emerald-900/80 text-emerald-200 border-emerald-900/70 hover:border-emerald-700/80 shadow-[0_0_20px_rgba(6,95,70,0.2)]"
                        }`}
                    >
                      {isDownloadingAll ? <Square className="w-4 h-4 fill-current" /> : <Download className="w-4 h-4" />}
                      {isDownloadingAll ? "Cancel ZIP Download" : "Download Playlist ZIP"}
                    </button>
                  </div>
                </div>
                {isDownloadingAll && (
                  <div className="mt-4">
                    <div className="mb-2 flex items-center justify-between text-xs font-semibold text-zinc-400">
                      <span>ZIP Download Progress</span>
                      <span className="text-emerald-300">{Math.round(playlistDownloadProgress)}%</span>
                    </div>
                    <Progress value={playlistDownloadProgress} className={progressBarClassName} />
                  </div>
                )}
              </div>

              <ScrollArea className="flex-1 w-full">
                <div className="p-2 md:p-4 space-y-1">
                  {tracks.map((track, idx) => (
                    <div
                      key={track.id}
                      onClick={() => setSelectedTrack(track)}
                      className={`group relative flex items-center gap-3 md:gap-4 p-3 md:p-4 rounded-2xl cursor-pointer transition-all duration-200 border border-transparent ${selectedTrack?.id === track.id ? 'bg-emerald-950/45 border-emerald-900/60 shadow-[0_0_15px_rgba(6,95,70,0.18)]' : 'hover:bg-[#0d1913] hover:border-emerald-950/50'}`}
                    >
                      <div className="shrink-0 flex items-center ml-auto">
                        <div className={`mr-2 shrink-0 overflow-hidden transition-all duration-200 ${allTracksSelected ? "w-9 opacity-100 md:w-0 md:group-hover:w-9 md:group-hover:opacity-100" : "w-9 opacity-100"}`}>
                          <button
                            onClick={(e) => {
                              e.stopPropagation()
                              toggleTrackSelection(track.id)
                            }}
                            className={`h-8 w-8 rounded-lg border transition-all duration-200 flex items-center justify-center ${selectedTrackIds.includes(track.id)
                              ? "bg-emerald-950/80 border-emerald-700/80 text-emerald-200"
                              : "bg-zinc-900/70 border-zinc-700/70 text-zinc-500 hover:text-emerald-200 hover:border-emerald-800/70"
                              }`}
                            aria-label={selectedTrackIds.includes(track.id) ? "Deselect song" : "Select song"}
                          >
                            {selectedTrackIds.includes(track.id) ? (
                              <Check className="w-4 h-4 stroke-[3]" />
                            ) : null}
                          </button>
                        </div>
                        <span className={`w-5 md:w-6 text-center text-xs md:text-sm font-medium ${selectedTrack?.id === track.id ? 'text-emerald-300' : 'text-zinc-500 group-hover:text-zinc-400'}`}>
                          {idx + 1}
                        </span>
                      </div>

                      {track.cover ? (
                        <div className="relative w-11 h-11 md:w-14 md:h-14 rounded-xl overflow-hidden shrink-0 shadow-md transition-transform duration-200 group-hover:translate-x-1">
                          <Image src={track.cover} alt="" fill className="object-cover" unoptimized />
                          {streamingTrackId === track.id && isPlaying && (
                            <div className="absolute inset-0 bg-black/35 flex items-center justify-center gap-1">
                              <div className="w-1.5 h-5 bg-emerald-500 rounded-full animate-smooth-bounce" style={{ animationDelay: '0ms' }} />
                              <div className="w-1.5 h-7 bg-emerald-500 rounded-full animate-smooth-bounce" style={{ animationDelay: '150ms' }} />
                              <div className="w-1.5 h-4 bg-emerald-500 rounded-full animate-smooth-bounce" style={{ animationDelay: '300ms' }} />
                            </div>
                          )}
                        </div>
                      ) : (
                        <div className="w-11 h-11 md:w-14 md:h-14 rounded-xl bg-zinc-900 flex items-center justify-center shrink-0 transition-transform duration-200 group-hover:translate-x-1">
                          <Music2 className="w-5 h-5 md:w-6 md:h-6 text-zinc-500" />
                        </div>
                      )}

                      <div className="flex-1 min-w-0 pr-3 md:pr-4 transition-transform duration-200 group-hover:translate-x-1">
                        <h3 className={`font-semibold truncate text-sm md:text-base ${selectedTrack?.id === track.id ? 'text-white' : 'text-zinc-200'}`}>
                          {track.title}
                        </h3>
                        <p className="text-xs md:text-sm text-zinc-400 truncate mt-0.5">{track.artists}</p>
                      </div>

                      <div className="shrink-0 flex items-center">
                        {trackProgress[track.id] !== undefined ? (
                          trackProgress[track.id] === -1 ? (
                            <span className="text-xs text-red-300 font-medium px-3 py-1.5 bg-red-950/40 rounded-lg border border-red-900/50">Error</span>
                          ) : (
                            <div className="flex items-center gap-2">
                              <span className="text-xs md:text-sm text-emerald-300 font-bold tracking-wider shrink-0">
                                {Math.round(trackProgress[track.id])}%
                              </span>
                              {isDownloadingTrack === track.id ? (
                                <button
                                  onClick={(e) => {
                                    e.stopPropagation()
                                    void cancelTrackDownload(track.id)
                                  }}
                                  className="shrink-0 p-2.5 rounded-xl border border-red-900/70 bg-red-950/70 text-red-200 hover:bg-red-900/80 hover:text-white hover:border-red-700/80 transition-all duration-300 transform active:scale-90 hover:scale-110 hover:shadow-[0_0_16px_rgba(127,29,29,0.35)] flex items-center justify-center"
                                  aria-label="Stop download"
                                >
                                  <Square className="w-5 h-5 fill-current" />
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
                            className="p-2.5 rounded-xl border border-red-900/70 bg-red-950/70 text-red-200 hover:bg-red-900/80 hover:text-white hover:border-red-700/80 transition-all duration-300 transform active:scale-90 hover:scale-110 hover:shadow-[0_0_16px_rgba(127,29,29,0.35)] flex items-center justify-center"
                            aria-label="Stop download"
                          >
                            <Square className="w-5 h-5 fill-current" />
                          </button>
                        ) : (
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              downloadTrack(track);
                            }}
                            className="p-2.5 rounded-xl border transition-all duration-300 transform active:scale-90 text-emerald-300 border-emerald-800/60 bg-emerald-950/30 opacity-100 hover:bg-emerald-950/45 hover:text-emerald-200 hover:border-emerald-700/60 hover:shadow-[0_0_15px_rgba(6,95,70,0.25)] hover:scale-110 hover:-translate-y-0.5 focus:opacity-100 flex items-center justify-center"
                            aria-label="Download track"
                          >
                            <Download className="w-5 h-5" />
                          </button>
                        )}
                      </div>
                      {trackProgress[track.id] !== undefined && trackProgress[track.id] !== -1 ? (
                        <div className="absolute inset-x-3 bottom-0 h-px overflow-hidden rounded-full bg-emerald-950/70 md:inset-x-4">
                          <div
                            className="h-full bg-emerald-500 shadow-[0_0_12px_rgba(16,185,129,0.7)] transition-[width] duration-300"
                            style={{ width: `${Math.max(0, Math.min(100, trackProgress[track.id]))}%` }}
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
                <div className="bg-[#09120d]/80 backdrop-blur-xl border border-emerald-950/60 rounded-[2rem] p-6 md:p-8 shadow-2xl shadow-black/30 flex flex-col items-center text-center animate-in fade-in zoom-in-95 duration-300">
                  <div className="w-full aspect-square rounded-2xl overflow-hidden relative shadow-2xl mb-8 group">
                    {selectedTrack.cover ? (
                      <Image src={selectedTrack.cover} alt="" fill className="object-cover transition-transform duration-700 group-hover:scale-105" unoptimized />
                    ) : (
                      <div className="w-full h-full bg-zinc-900 flex items-center justify-center">
                        <Music2 className="w-20 h-20 text-zinc-600" />
                      </div>
                    )}
                    <div className="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300" />
                  </div>

                  <h3 className="text-2xl font-bold text-white mb-2 leading-tight px-2">{selectedTrack.title}</h3>
                  <p className="text-zinc-400 font-medium text-base mb-8">{selectedTrack.artists}</p>

                <div className="w-full space-y-3">
                    {/* Stream / Preview Player */}
                    <div className="w-full rounded-2xl border border-emerald-900/50 bg-emerald-950/20 p-4 space-y-3">
                      <div className="flex items-center gap-3">
                        <button
                          id={`stream-btn-${selectedTrack.id}`}
                          onClick={() => toggleStream(selectedTrack)}
                          disabled={isLoadingStream && streamingTrackId !== selectedTrack.id}
                          className={`flex items-center gap-2 px-4 py-2.5 rounded-xl font-semibold text-sm transition-all duration-300 hover:scale-105 active:scale-95 border disabled:opacity-50 disabled:hover:scale-100 ${
                            streamingTrackId === selectedTrack.id
                              ? "bg-emerald-900/70 border-emerald-700/70 text-emerald-200 hover:bg-emerald-800/80"
                              : "bg-zinc-900/70 border-zinc-700/60 text-zinc-300 hover:bg-zinc-800/80 hover:text-white"
                          }`}
                          aria-label={streamingTrackId === selectedTrack.id && isPlaying ? "Pause preview" : "Play preview"}
                        >
                          {isLoadingStream && streamingTrackId === selectedTrack.id ? (
                            <Loader2 className="w-4 h-4 animate-spin" />
                          ) : streamingTrackId === selectedTrack.id && isPlaying ? (
                            <Pause className="w-4 h-4 fill-current" />
                          ) : (
                            <Play className="w-4 h-4 fill-current" />
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
                          <Radio className="w-3.5 h-3.5 opacity-60" />
                        </button>
                        {streamingTrackId === selectedTrack.id && (
                          <button
                            onClick={stopStream}
                            className="p-2 rounded-xl border border-zinc-700/60 bg-zinc-900/50 text-zinc-400 hover:text-white hover:bg-zinc-800/70 transition-all duration-200"
                            aria-label="Stop preview"
                          >
                            <Square className="w-3.5 h-3.5 fill-current" />
                          </button>
                        )}
                        <span className="ml-auto text-xs text-zinc-500 font-mono tabular-nums">
                          {streamingTrackId === selectedTrack.id && streamDuration > 0
                            ? `${Math.floor(streamProgress * streamDuration / 60).toString().padStart(2, "0")}:${Math.floor((streamProgress * streamDuration) % 60).toString().padStart(2, "0")} / ${Math.floor(streamDuration / 60).toString().padStart(2, "0")}:${Math.floor(streamDuration % 60).toString().padStart(2, "0")}`
                            : ""}
                        </span>
                      </div>
                      {streamingTrackId === selectedTrack.id && (
                        <div
                          className="relative h-1.5 w-full rounded-full bg-zinc-800 cursor-pointer overflow-hidden"
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
                            className="h-full bg-emerald-500 shadow-[0_0_8px_rgba(16,185,129,0.6)] transition-[width] duration-200 rounded-full"
                            style={{ width: `${streamProgress * 100}%` }}
                          />
                        </div>
                      )}
                    </div>

                    {/* YouTube Source Section */}
                    <div className="w-full rounded-2xl border border-zinc-800/70 bg-zinc-900/30 p-4 space-y-3">
                      <div className="flex items-center justify-between">
                        <p className="text-xs font-semibold uppercase tracking-wider text-zinc-500">YouTube Source</p>
                        <div className="flex items-center gap-1.5">
                          {youtubeUrls[selectedTrack.id] && (
                            <button
                              onClick={() => resetYtUrl(selectedTrack.id)}
                              className="p-1.5 rounded-lg text-zinc-500 hover:text-zinc-300 hover:bg-zinc-800/60 transition-all duration-200"
                              title="Reset to auto-detected source"
                              aria-label="Reset YouTube source"
                            >
                              <RotateCcw className="w-3.5 h-3.5" />
                            </button>
                          )}
                          {!isEditingYtUrl ? (
                            <button
                              onClick={() => startEditingYtUrl(selectedTrack)}
                              className="p-1.5 rounded-lg text-zinc-500 hover:text-emerald-400 hover:bg-emerald-950/40 transition-all duration-200"
                              title="Edit YouTube URL"
                              aria-label="Edit YouTube source URL"
                            >
                              <Pencil className="w-3.5 h-3.5" />
                            </button>
                          ) : (
                            <button
                              onClick={cancelEditingYtUrl}
                              className="p-1.5 rounded-lg text-zinc-500 hover:text-zinc-300 hover:bg-zinc-800/60 transition-all duration-200"
                              aria-label="Cancel editing"
                            >
                              <X className="w-3.5 h-3.5" />
                            </button>
                          )}
                        </div>
                      </div>

                      {isEditingYtUrl ? (
                        <div className="space-y-2">
                          <input
                            id={`yt-url-input-${selectedTrack.id}`}
                            type="url"
                            placeholder="https://www.youtube.com/watch?v=..."
                            value={ytUrlDraft}
                            onChange={(e) => setYtUrlDraft(e.target.value)}
                            onKeyDown={(e) => {
                              if (e.key === "Enter") saveYtUrl(selectedTrack)
                              if (e.key === "Escape") cancelEditingYtUrl()
                            }}
                            className="w-full bg-zinc-900/80 border border-zinc-700/60 rounded-xl px-3 py-2 text-xs text-zinc-200 placeholder:text-zinc-600 outline-none focus:border-emerald-700/70 focus:ring-1 focus:ring-emerald-900/50 transition-all"
                            autoFocus
                          />
                          <button
                            onClick={() => saveYtUrl(selectedTrack)}
                            disabled={isResolvingYtUrl}
                            className="w-full py-2 rounded-xl bg-emerald-900/70 hover:bg-emerald-800/80 border border-emerald-700/60 text-emerald-200 text-xs font-semibold transition-all duration-200 hover:scale-[1.02] disabled:opacity-60 flex items-center justify-center gap-2"
                          >
                            {isResolvingYtUrl ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Check className="w-3.5 h-3.5" />}
                            {isResolvingYtUrl ? "Resolving…" : "Save URL"}
                          </button>
                        </div>
                      ) : ytUrlMeta[selectedTrack.id] ? (
                        <div className="flex items-center gap-3">
                          {ytUrlMeta[selectedTrack.id]!.thumbnail && (
                            <div className="relative w-14 h-10 rounded-lg overflow-hidden shrink-0 border border-zinc-700/50">
                              <Image src={ytUrlMeta[selectedTrack.id]!.thumbnail} alt="" fill className="object-cover" unoptimized />
                            </div>
                          )}
                          <div className="min-w-0 flex-1">
                            <p className="text-xs font-medium text-zinc-200 truncate">{ytUrlMeta[selectedTrack.id]!.title}</p>
                            <p className="text-[11px] text-zinc-500 truncate">{ytUrlMeta[selectedTrack.id]!.channel}</p>
                          </div>
                          <a
                            href={youtubeUrls[selectedTrack.id]}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="shrink-0 p-1.5 rounded-lg text-zinc-500 hover:text-zinc-200 hover:bg-zinc-800/60 transition-all duration-200"
                            aria-label="Open on YouTube"
                          >
                            <ExternalLink className="w-3.5 h-3.5" />
                          </a>
                        </div>
                      ) : (
                        <div className="flex items-center gap-2">
                          {(youtubeUrls[selectedTrack.id] || selectedTrack.youtubeUrl) ? (
                            <a
                              href={youtubeUrls[selectedTrack.id] || selectedTrack.youtubeUrl!}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="flex items-center gap-1.5 text-xs text-zinc-400 hover:text-emerald-400 transition-colors min-w-0"
                            >
                              <ExternalLink className="w-3 h-3 shrink-0" />
                              <span className="truncate">{youtubeUrls[selectedTrack.id] ? youtubeUrls[selectedTrack.id] : selectedTrack.youtubeUrl}</span>
                            </a>
                          ) : (
                            <p className="text-xs text-zinc-600 italic">Auto-detected — click ✏️ to override</p>
                          )}
                        </div>
                      )}
                    </div>

                    <button
                      onClick={() => {
                        if (isDownloadingTrack === selectedTrack.id) void cancelTrackDownload(selectedTrack.id);
                        else downloadTrack(selectedTrack);
                      }}
                      className={`w-full py-4 rounded-2xl ${isDownloadingTrack === selectedTrack.id ? 'bg-red-950/35 text-red-300 hover:bg-red-950/55 border border-red-900/50' : 'bg-emerald-900/80 text-emerald-50 hover:bg-emerald-800/85 border border-emerald-700/70'} font-bold transition-all duration-300 hover:scale-105 flex justify-center items-center gap-2 shadow-[0_0_20px_rgba(6,95,70,0.25)] hover:shadow-[0_0_35px_rgba(6,95,70,0.35)] disabled:opacity-70 disabled:hover:scale-100`}
                    >
                      {isDownloadingTrack === selectedTrack.id ? (
                        <>
                          <Square className="w-5 h-5 fill-current" />
                          Cancel Download
                        </>
                      ) : (
                        <>
                          <Download className="w-5 h-5" />
                          Download MP3
                        </>
                      )}
                    </button>

                    <div className="text-xs text-zinc-500 font-medium pt-2">
                      {selectedTrack.album && <p>Album: {selectedTrack.album}</p>}
                    </div>
                  </div>
                </div>
              ) : (
                <div className="bg-[#09120d]/55 border border-emerald-950/50 border-dashed rounded-[2rem] p-8 flex flex-col items-center justify-center text-center h-[500px]">
                  <div className="w-20 h-20 bg-zinc-900/70 rounded-full flex items-center justify-center mb-6">
                    <Music2 className="w-10 h-10 text-zinc-600" />
                  </div>
                  <h3 className="text-lg font-semibold text-zinc-300 mb-2">No track selected</h3>
                  <p className="text-zinc-500 font-medium max-w-[200px]">Select a track from the list to view details and download.</p>
                </div>
              )}
            </div>

          </div>
        )}
      </main>
    </div>
  )
}
