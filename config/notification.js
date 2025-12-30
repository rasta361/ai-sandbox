// OpenCode Plugin: Audio notifications

export const NotificationPlugin = async ({ project, client, $, directory, worktree }) => {
  return {
    event: async ({ event }) => {
      // Notify on session completion
      if (event.type === "session.idle") {
        await $`edge-tts -t 'AI done' --write-media - | ffmpeg -loglevel quiet -i - -f s16le -ar 24000 -ac 1 - | paplay --raw --rate 24000 --channels 1`
      }
      // Notify when permission is needed (waiting for input)
      if (event.type === "permission.updated") {
        await $`edge-tts -t 'Input needed' --write-media - | ffmpeg -loglevel quiet -i - -f s16le -ar 24000 -ac 1 - | paplay --raw --rate 24000 --channels 1`
      }
    },
  }
}
