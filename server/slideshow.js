let state = {
  index: 0,
  playing: true
};

function getState(req, res) {
  res.json(state);
}

function control(req, res) {
  const { action } = req.body;

  if (action === 'next') state.index++;
  if (action === 'prev') state.index = Math.max(0, state.index - 1);
  if (action === 'toggle') state.playing = !state.playing;

  res.json(state);
}

module.exports = { getState, control };
