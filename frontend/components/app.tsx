"use client"

import { useEffect, useRef, useState } from "react"
import {
  Music2,
  Download,
  Loader2,
  Sparkles,
  Search,
  Square
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
}

export default function SpotifyDownloaderApp() {
  const [playlistLink, setPlaylistLink] = useState("")

  useEffect(() => {
    setPlaylistLink("")
  }, [])
  const [downloadProgress, setDownloadProgress] = useState(0)
  const [songsDownloaded, setSongsDownloaded] = useState(0)
  const [totalSongs, setTotalSongs] = useState(0)
  const [playlistName, setPlaylistName] = useState("")
  const [isProcessing, setIsProcessing] = useState(false)
  const [statusMessage, setStatusMessage] = useState("Paste a Spotify URL to begin")
  const [tracks, setTracks] = useState<Track[]>([])
  const [selectedTrack, setSelectedTrack] = useState<Track | null>(null)
  const [isDownloadingTrack, setIsDownloadingTrack] = useState<string | null>(null)
  const [activeAbortController, setActiveAbortController] = useState<AbortController | null>(null)
  const [isDownloadingAll, setIsDownloadingAll] = useState(false)
  const [activePlaylistJobId, setActivePlaylistJobId] = useState<string | null>(null)
  const [trackProgress, setTrackProgress] = useState<Record<string, number>>({})
  const trackProgressIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const playlistProgressIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const playlistStatusAbortRef = useRef<AbortController | null>(null)
  const playlistCancelRequestedRef = useRef(false)
  const RAW_API_URL = process.env.NEXT_PUBLIC_API_URL || "http://127.0.0.1:5000"
  let LOCAL_API = RAW_API_URL.replace(/\/+$/, "").replace(/\/api$/, "")
  if (!LOCAL_API.startsWith("http") && !LOCAL_API.startsWith("//") && LOCAL_API !== "") {
    LOCAL_API = `https://${LOCAL_API}`
  }

  const progressBarClassName = "h-2 bg-zinc-800 [&>div]:bg-gradient-to-r [&>div]:from-green-500 [&>div]:to-emerald-500 rounded-full"

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

  const cancelPlaylistDownload = async () => {
    playlistCancelRequestedRef.current = true
    clearPlaylistProgressInterval()
    playlistStatusAbortRef.current?.abort()
    toast.loading("Cancelling playlist download...", { id: "download-toast" })

    if (!activePlaylistJobId) {
      return
    }

    try {
      await fetch(`${LOCAL_API}/api/cancel-playlist/${activePlaylistJobId}`, { method: "POST" })
    } catch (e) {
      console.error("Failed to notify backend about playlist cancellation", e)
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

      const res = await fetch(`${LOCAL_API}/api/download-track`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(track),
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
        fetch(`${LOCAL_API}/api/cancel-track/${track.id}`, { method: 'POST' }).catch(() => {})
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
    if (tracks.length === 0) return
    try {
      setIsDownloadingAll(true)
      setActivePlaylistJobId(null)
      playlistCancelRequestedRef.current = false
      playlistStatusAbortRef.current = new AbortController()
      toast.loading("Downloading playlist, this might take a while...", { id: "download-toast" })

      setTrackProgress((prev) => {
        const ns = { ...prev }
        tracks.forEach(track => {
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
              tracks.forEach(t => {
                if (data[t.id] !== undefined) {
                  ns[t.id] = data[t.id]
                }
              })
              return ns
            })
          }
        } catch (e) { }
      }, 1000)

      const res = await fetch(`${LOCAL_API}/api/download-playlist-zip`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ tracks, playlistName }),
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
        await fetch(`${LOCAL_API}/api/cancel-playlist/${job_id}`, { method: "POST" }).catch(() => {})
        setTrackProgress({})
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
        return
      }

      if (success) {
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
      }, 1500)
    } catch (err: any) {
      console.error(err)
      toast.error(err.message || "Playlist download failed", { id: "download-toast" })
      setTrackProgress({})
    } finally {
      clearPlaylistProgressInterval()
      playlistStatusAbortRef.current?.abort()
      playlistStatusAbortRef.current = null
      playlistCancelRequestedRef.current = false
      setActivePlaylistJobId(null)
      setIsDownloadingAll(false)
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
    <div className="min-h-screen bg-[#09090b] text-zinc-50 font-sans selection:bg-zinc-800">
      {/* Background Gradient */}
      <div className="fixed inset-0 z-0 overflow-hidden pointer-events-none">
        <div className="absolute -top-[25%] -left-[10%] w-[80%] h-[80%] rounded-full bg-green-500/20 blur-[140px] mix-blend-screen" />
        <div className="absolute top-[20%] -right-[10%] w-[60%] h-[60%] rounded-full bg-emerald-500/20 blur-[140px] mix-blend-screen" />
      </div>

      <Toaster
        position="top-center"
        toastOptions={{
          style: {
            background: "#09090b",
            color: "#f4f4f5",
            border: "1px solid rgba(34, 197, 94, 0.2)",
            borderRadius: "1rem",
            boxShadow: "0 0 20px rgba(34, 197, 94, 0.1)",
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

      <main className="relative z-10 max-w-[1200px] mx-auto px-4 py-12 md:py-20 flex flex-col min-h-screen">

        {/* Header / Input Section */}
        <div className={`transition-all duration-700 ease-in-out flex flex-col items-center justify-center ${tracks.length > 0 ? "mb-12" : "flex-1 mb-0"}`}>

          <div className="text-center space-y-4 mb-10">
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-gradient-to-r from-green-500/10 to-emerald-500/10 border border-green-500/20 text-xs font-medium mb-2">
              <Sparkles className="w-3 h-3 text-emerald-400" />
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-green-400 to-emerald-400">Premium Audio Downloader</span>
            </div>
            <h1 className="text-4xl md:text-6xl font-bold tracking-tighter text-transparent bg-clip-text bg-gradient-to-br from-white to-green-100/80 pb-2 leading-normal">
              Download any playlist.
            </h1>
            <p className="text-zinc-400 max-w-lg mx-auto text-base md:text-lg">
              Paste your Spotify link below and get high-quality MP3s instantly in a beautiful format.
            </p>
          </div>

          <div className="w-full max-w-2xl relative group">
            <div className="absolute -inset-0.5 bg-gradient-to-r from-green-500/30 to-emerald-500/30 rounded-[2rem] blur opacity-0 group-hover:opacity-100 transition duration-500"></div>
            <div className="relative flex flex-col sm:flex-row items-center bg-zinc-900/90 backdrop-blur-xl border border-zinc-800 rounded-3xl p-2 shadow-2xl">
              <div className="w-full flex items-center pl-4 pr-2 py-1">
                <Search className="w-5 h-5 text-zinc-500 shrink-0" />
                <input
                  type="text"
                  placeholder="https://open.spotify.com/playlist/..."
                  value={playlistLink}
                  onChange={(e) => setPlaylistLink(e.target.value)}
                  onKeyDown={(e) => e.key === "Enter" && !isProcessing && handleProcess()}
                  className="flex-1 bg-transparent border-none outline-none text-zinc-100 px-4 py-3 placeholder:text-zinc-600 focus:ring-0 w-full"
                />
              </div>
              <button
                onClick={handleProcess}
                disabled={isProcessing}
                className="w-full sm:w-auto bg-gradient-to-r from-green-500 to-emerald-500 text-black px-8 py-4 rounded-2xl font-semibold hover:from-green-400 hover:to-emerald-400 transition-all duration-300 hover:scale-105 disabled:opacity-70 flex items-center justify-center gap-2 shrink-0 shadow-[0_0_20px_rgba(34,197,94,0.2)] hover:shadow-[0_0_35px_rgba(34,197,94,0.4)] disabled:hover:scale-100"
              >
                {isProcessing ? <Loader2 className="w-5 h-5 animate-spin" /> : <><Download className="w-5 h-5" /> <span className="font-bold">Fetch</span></>}
              </button>
            </div>
          </div>

          {/* Progress Indicator */}
          {(isProcessing || downloadProgress > 0) && (
            <div className="w-full max-w-2xl mt-8 p-6 bg-zinc-900/50 border border-zinc-800/50 rounded-2xl backdrop-blur-md">
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
          <div className="grid lg:grid-cols-[1fr_360px] gap-6 items-start animate-in fade-in slide-in-from-bottom-8 duration-700">

            {/* Track List */}
            <div className="bg-zinc-900/40 backdrop-blur-xl border border-zinc-800/60 rounded-[2rem] overflow-hidden shadow-2xl flex flex-col h-[700px]">
              <div className="p-6 md:p-8 border-b border-zinc-800/60 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 bg-zinc-900/40">
                <div>
                  <h2 className="text-2xl font-bold text-white tracking-tight">{playlistName || "Track List"}</h2>
                  <p className="text-sm text-zinc-400 mt-1">{tracks.length} tracks found in this playlist</p>
                </div>
                <button
                  onClick={isDownloadingAll ? cancelPlaylistDownload : downloadAll}
                  disabled={!isDownloadingAll && tracks.length === 0}
                  className="w-full sm:w-auto flex items-center justify-center gap-2 px-6 py-3 bg-gradient-to-r from-green-500/10 to-emerald-500/10 hover:from-green-500/20 hover:to-emerald-500/20 text-emerald-400 rounded-xl text-sm font-semibold transition-all duration-300 hover:scale-[1.02] border border-green-500/20 hover:border-emerald-500/40 disabled:opacity-50 disabled:hover:scale-100"
                >
                  {isDownloadingAll ? <Square className="w-4 h-4 fill-current" /> : <Download className="w-4 h-4" />}
                  {isDownloadingAll ? "Cancel ZIP Download" : "Download Entire ZIP"}
                </button>
              </div>

              <ScrollArea className="flex-1 w-full">
                <div className="p-3 md:p-4 space-y-1">
                  {tracks.map((track, idx) => (
                    <div
                      key={track.id}
                      onClick={() => setSelectedTrack(track)}
                      className={`group relative flex items-center gap-4 p-3 md:p-4 rounded-2xl cursor-pointer transition-all duration-200 border border-transparent ${selectedTrack?.id === track.id ? 'bg-gradient-to-r from-green-500/10 to-emerald-500/10 border-green-500/30 shadow-[0_0_15px_rgba(34,197,94,0.05)]' : 'hover:bg-zinc-800/40 hover:border-zinc-700/30'}`}
                    >
                      <span className={`w-6 text-center text-sm font-medium ${selectedTrack?.id === track.id ? 'text-transparent bg-clip-text bg-gradient-to-r from-green-400 to-emerald-400' : 'text-zinc-500 group-hover:text-zinc-400'}`}>
                        {idx + 1}
                      </span>

                      {track.cover ? (
                        <div className="relative w-12 h-12 md:w-14 md:h-14 rounded-xl overflow-hidden shrink-0 shadow-md">
                          <Image src={track.cover} alt="" fill className="object-cover" unoptimized />
                          {selectedTrack?.id === track.id && (
                            <div className="absolute inset-0 bg-black/40 flex items-center justify-center">
                              <div className="w-1 h-3 bg-gradient-to-t from-green-400 to-emerald-400 rounded-full animate-bounce mx-0.5" style={{ animationDelay: '0ms' }} />
                              <div className="w-1 h-4 bg-gradient-to-t from-green-400 to-emerald-400 rounded-full animate-bounce mx-0.5" style={{ animationDelay: '150ms' }} />
                              <div className="w-1 h-2 bg-gradient-to-t from-green-400 to-emerald-400 rounded-full animate-bounce mx-0.5" style={{ animationDelay: '300ms' }} />
                            </div>
                          )}
                        </div>
                      ) : (
                        <div className="w-12 h-12 md:w-14 md:h-14 rounded-xl bg-zinc-800 flex items-center justify-center shrink-0">
                          <Music2 className="w-6 h-6 text-zinc-500" />
                        </div>
                      )}

                      <div className="flex-1 min-w-0 pr-4">
                        <h3 className={`font-semibold truncate text-base ${selectedTrack?.id === track.id ? 'text-white' : 'text-zinc-200'}`}>
                          {track.title}
                        </h3>
                        <p className="text-sm text-zinc-400 truncate mt-0.5">{track.artists}</p>
                      </div>

                      <div className="shrink-0 flex items-center">
                        {trackProgress[track.id] !== undefined ? (
                          trackProgress[track.id] === -1 ? (
                            <span className="text-xs text-red-400 font-medium px-3 py-1.5 bg-red-400/10 rounded-lg border border-red-400/20">Error</span>
                          ) : (
                            <div className="flex flex-col items-end gap-2">
                              <div className="flex flex-col items-end gap-1.5 w-48 md:w-64">
                                <span className="text-xs md:text-sm text-transparent bg-clip-text bg-gradient-to-r from-green-400 to-emerald-400 font-bold tracking-wider">{Math.round(trackProgress[track.id])}%</span>
                                <div className="flex items-center gap-2 w-full">
                                  <Progress value={trackProgress[track.id]} className={progressBarClassName} />
                                  {isDownloadingTrack === track.id ? (
                                    <button
                                      onClick={(e) => {
                                        e.stopPropagation()
                                        void cancelTrackDownload(track.id)
                                      }}
                                      className="shrink-0 p-2.5 rounded-xl border border-red-500/40 bg-red-500/10 text-red-400 hover:bg-gradient-to-r hover:from-red-500/20 hover:to-orange-500/20 hover:text-red-400 hover:border-red-500/50 transition-all duration-300 transform active:scale-90 hover:scale-110 hover:shadow-[0_0_15px_rgba(239,68,68,0.2)] flex items-center justify-center"
                                      aria-label="Stop download"
                                    >
                                      <Square className="w-5 h-5 fill-current" />
                                    </button>
                                  ) : null}
                                </div>
                              </div>
                            </div>
                          )
                        ) : isDownloadingTrack === track.id ? (
                          <button
                            onClick={(e) => {
                              e.stopPropagation()
                              void cancelTrackDownload(track.id)
                            }}
                            className="p-2.5 rounded-xl border border-red-500/40 bg-red-500/10 text-red-400 hover:bg-gradient-to-r hover:from-red-500/20 hover:to-orange-500/20 hover:text-red-400 hover:border-red-500/50 transition-all duration-300 transform active:scale-90 hover:scale-110 hover:shadow-[0_0_15px_rgba(239,68,68,0.2)] flex items-center justify-center"
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
                            className={`p-2.5 rounded-xl border transition-all duration-300 transform active:scale-90 ${selectedTrack?.id === track.id ? 'text-emerald-400 border-green-500/30 bg-green-500/5 opacity-100' : 'text-zinc-500 border-zinc-700/50 bg-zinc-800/30 opacity-60 group-hover:opacity-100'} hover:bg-gradient-to-r hover:from-green-500/20 hover:to-emerald-500/20 hover:text-emerald-300 hover:border-green-500/40 hover:shadow-[0_0_15px_rgba(34,197,94,0.2)] hover:scale-110 hover:-translate-y-0.5 focus:opacity-100 flex items-center justify-center`}
                            aria-label="Download track"
                          >
                            <Download className="w-5 h-5" />
                          </button>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              </ScrollArea>
            </div>

            {/* Now Playing / Selection */}
            <div className="sticky top-6">
              {selectedTrack ? (
                <div className="bg-zinc-900/60 backdrop-blur-xl border border-zinc-800/60 rounded-[2rem] p-6 md:p-8 shadow-2xl flex flex-col items-center text-center animate-in fade-in zoom-in-95 duration-300">
                  <div className="w-full aspect-square rounded-2xl overflow-hidden relative shadow-2xl mb-8 group">
                    {selectedTrack.cover ? (
                      <Image src={selectedTrack.cover} alt="" fill className="object-cover transition-transform duration-700 group-hover:scale-105" unoptimized />
                    ) : (
                      <div className="w-full h-full bg-zinc-800 flex items-center justify-center">
                        <Music2 className="w-20 h-20 text-zinc-600" />
                      </div>
                    )}
                    <div className="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300" />
                  </div>

                  <h3 className="text-2xl font-bold text-white mb-2 leading-tight px-2">{selectedTrack.title}</h3>
                  <p className="text-zinc-400 font-medium text-base mb-8">{selectedTrack.artists}</p>

                  <div className="w-full space-y-3">
                     <button
                       onClick={() => {
                         if (isDownloadingTrack === selectedTrack.id) void cancelTrackDownload(selectedTrack.id);
                         else downloadTrack(selectedTrack);
                       }}
                      className={`w-full py-4 rounded-2xl ${isDownloadingTrack === selectedTrack.id ? 'bg-red-500/10 text-red-400 hover:bg-red-500/20 border border-red-500/30' : 'bg-gradient-to-r from-green-500 to-emerald-500 text-black hover:from-green-400 hover:to-emerald-400'} font-bold transition-all duration-300 hover:scale-105 flex justify-center items-center gap-2 shadow-[0_0_20px_rgba(34,197,94,0.2)] hover:shadow-[0_0_35px_rgba(34,197,94,0.4)] disabled:opacity-70 disabled:hover:scale-100`}
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
                <div className="bg-zinc-900/30 border border-zinc-800/50 border-dashed rounded-[2rem] p-8 flex flex-col items-center justify-center text-center h-[500px]">
                  <div className="w-20 h-20 bg-zinc-800/50 rounded-full flex items-center justify-center mb-6">
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
