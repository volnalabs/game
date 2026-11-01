class_name SoundSynth
extends RefCounted
## Every sound of the game is synthesized here from a short description (data/audio/sounds.json) —
## there are no audio files. A sound is a sum of layers; each layer is an oscillator (sine, triangle,
## square, saw or noise) with a pitch glide, optional vibrato, an attack/decay envelope, a one-pole
## low-pass filter and a start delay. The result is a 16-bit mono AudioStreamWAV. Deterministic: noise
## comes from a hash of the sample index and the layer seed, so a sound is identical every time.

const MIX_RATE := 22050


## Builds the stream for one sound definition {"layers": [...], "gain": float, "loop": bool}.
static func build(def: Dictionary) -> AudioStreamWAV:
	var layers: Array = def.get("layers", [])
	var length := 0.0
	for l: Dictionary in layers:
		length = maxf(length, float(l.get("delay", 0.0)) + float(l.get("attack", 0.005)) + float(l.get("decay", 0.2)))
	length = clampf(length, 0.02, 8.0)
	var n := int(length * MIX_RATE)
	var loop := bool(def.get("loop", false))
	# A loop is rendered a little longer and its head crossfaded with that continuation, so the
	# last sample flows into the first without a click.
	var xfade := int(0.25 * MIX_RATE) if loop else 0
	var buf := PackedFloat32Array()
	buf.resize(n + xfade)
	buf.fill(0.0)
	for l: Dictionary in layers:
		_render_layer(buf, l, n if loop else -1)
	if loop:
		for i in xfade:
			var w := float(i) / float(xfade)
			buf[i] = buf[i] * w + buf[n + i] * (1.0 - w)
		buf.resize(n)
	# Normalise to the definition's gain (never clip).
	var peak := 0.0
	for v in buf:
		peak = maxf(peak, absf(v))
	var gain := float(def.get("gain", 0.8))
	var k := gain / peak if peak > 0.0001 else 0.0
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var s := clampi(int(round(buf[i] * k * 32767.0)), -32768, 32767)
		data.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav


## `hold_from` >= 0: the envelope stays open past that sample (the crossfade tail of a loop).
static func _render_layer(buf: PackedFloat32Array, l: Dictionary, hold_from: int = -1) -> void:
	var wave := String(l.get("wave", "sine"))
	var f0 := float(l.get("freq", 440.0))
	var f1 := float(l.get("freq_end", f0))
	var delay := float(l.get("delay", 0.0))
	var attack := maxf(float(l.get("attack", 0.005)), 0.0005)
	var decay := maxf(float(l.get("decay", 0.2)), 0.001)
	var amp := float(l.get("amp", 1.0))
	var vib_rate := float(l.get("vibrato_rate", 0.0))
	var vib_depth := float(l.get("vibrato_depth", 0.0))
	var cutoff := float(l.get("lowpass", 0.0))
	var seed := int(l.get("seed", 1))
	var curve := float(l.get("curve", 2.0))
	var start := int(delay * MIX_RATE)
	var count := int((attack + decay) * MIX_RATE)
	if hold_from >= 0:
		count = buf.size() - start
	# One-pole low-pass: y += a * (x - y), a from the cutoff frequency.
	var a := 1.0
	if cutoff > 0.0:
		a = 1.0 - exp(-TAU * cutoff / MIX_RATE)
	var phase := 0.0
	var y := 0.0
	var held := 0.0
	for i in count:
		var j := start + i
		if j >= buf.size():
			break
		var t := float(i) / MIX_RATE
		var p := clampf(t / (attack + decay), 0.0, 1.0) if hold_from < 0 else fmod(t, attack + decay) / (attack + decay)
		# Exponential-ish glide from f0 to f1 over the layer.
		var f := f0 * pow(f1 / f0, p) if f0 > 0.0 and f1 > 0.0 else lerpf(f0, f1, p)
		if vib_rate > 0.0:
			f *= 1.0 + vib_depth * sin(TAU * vib_rate * t)
		phase = fmod(phase + f / MIX_RATE, 1.0)
		var x := 0.0
		match wave:
			"sine":
				x = sin(TAU * phase)
			"triangle":
				x = 4.0 * absf(phase - 0.5) - 1.0
			"square":
				x = 1.0 if phase < 0.5 else -1.0
			"saw":
				x = 2.0 * phase - 1.0
			"noise":
				# Sample-and-hold noise at the layer's frequency (higher = brighter hiss).
				var step := maxi(1, int(MIX_RATE / maxf(f, 1.0)))
				if i % step == 0:
					held = _hash_noise(j, seed)
				x = held
		y += a * (x - y)
		var env := 0.0
		if t < attack:
			env = t / attack
		elif hold_from >= 0 and curve <= 0.0:
			env = 1.0
		else:
			env = pow(maxf(0.0, 1.0 - (t - attack) / decay), curve)
		buf[j] += y * env * amp


static func _hash_noise(i: int, seed: int) -> float:
	var h := (i * 374761393 + seed * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h % 20001) / 10000.0 - 1.0
