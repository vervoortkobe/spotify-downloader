/** @type {import('next').NextConfig} */
const nextConfig = {
  allowedDevOrigins: ["127.0.0.1", "localhost", "192.168.1.5"],
  images: {
    remotePatterns: [
      {
        protocol: "https",
        hostname: "i.scdn.co",
      },
      {
        protocol: "https",
        hostname: "**.scdn.co",
      },
      {
        protocol: "https",
        hostname: "**.spotifycdn.com",
      },
      {
        protocol: "https",
        hostname: "i.ytimg.com",
      },
      {
        protocol: "https",
        hostname: "img.youtube.com",
      },
      {
        protocol: "https",
        hostname: "i1.sndcdn.com",
      },
      {
        protocol: "https",
        hostname: "images.soundcloudimages.com",
      },
    ],
  },
}

export default nextConfig
