let state = {
  index: 0,
  playing: true,
};

let broadcastCallback = null;

function setBroadcastCallback(callback) {
  broadcastCallback = callback;
}

function broadcastState() {
  if (broadcastCallback) {
    broadcastCallback(state);
  }
}

function getState(req, res) {
  res.json(state);
}

function getStateSync() {
  return state;
}

function control(req, res) {
  const { action } = req.body;

  if (action === 'next') state.index++;
  if (action === 'prev') state.index = Math.max(0, state.index - 1);
  if (action === 'toggle') state.playing = !state.playing;

  // Broadcast state change to all connected WebSocket clients
  broadcastState();

  res.json(state);
}

module.exports = { getState, getStateSync, control, setBroadcastCallback };
