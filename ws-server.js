const WebSocket = require('ws');
const dgram = require('dgram');

const LED_DEVICES = [
  { ip: '192.168.68.60', count: 89 },
  { ip: '192.168.68.64', count: 90 },
  { ip: '192.168.68.50', count: 81 },
];

let isEnabled = false;
let currentEffect = 'linear-fill';

const udpSocket = dgram.createSocket('udp4');

// === HSV and Effects ===
function hsvToRgb(h, s, v) {
  const i = Math.floor(h * 6);
  const f = h * 6 - i;
  const p = v * (1 - s);
  const q = v * (1 - f * s);
  const t = v * (1 - (1 - f * s));
  let r, g, b;
  switch (i % 6) {
    case 0: [r, g, b] = [v, t, p]; break;
    case 1: [r, g, b] = [q, v, p]; break;
    case 2: [r, g, b] = [p, v, t]; break;
    case 3: [r, g, b] = [p, q, v]; break;
    case 4: [r, g, b] = [t, p, v]; break;
    case 5: [r, g, b] = [v, p, q]; break;
  }
  return [r, g, b].map(x => Math.floor(x * 255));
}

function renderPacketLinear(count, volume, hue) {
  const lit = Math.floor(volume * count);
  const leds = [];

  for (let i = 0; i < count; i++) {
    if (i < lit) {
      const adjustedHue = (hue + i / count) % 1.0;
      const [r, g, b] = hsvToRgb(adjustedHue, 1, 1);
      leds.push(r, g, b);
    } else {
      leds.push(0, 0, 0);
    }
  }

  return Buffer.from([0x02, 0x01, ...leds]);
}

function renderPacketCenterPulse(count, volume, hue) {
  const lit = Math.floor(volume * count);
  const leds = new Array(count * 3).fill(0);
  const center = Math.floor(count / 2);

  for (let i = 0; i < lit; i++) {
    const offset = Math.floor(i / 2);
    const left = center - offset;
    const right = center + offset;
    const adjustedHue = (hue + offset / count) % 1.0;
    const [r, g, b] = hsvToRgb(adjustedHue, 1, 1);

    if (left >= 0) {
      leds[left * 3] = r;
      leds[left * 3 + 1] = g;
      leds[left * 3 + 2] = b;
    }
    if (right < count) {
      leds[right * 3] = r;
      leds[right * 3 + 1] = g;
      leds[right * 3 + 2] = b;
    }
  }

  return Buffer.from([0x02, 0x01, ...leds]);
}

function renderPacketRainbowFlow(count, volume, hue) {
  const leds = [];
  for (let i = 0; i < count; i++) {
    const shiftHue = (hue + i / count) % 1.0;
    const [r, g, b] = hsvToRgb(shiftHue, 1, volume);
    leds.push(r, g, b);
  }
  return Buffer.from([0x02, 0x01, ...leds]);
}

function renderPacketWavePulseFlow(count, volume, hue) {
  const leds = new Array(count * 3).fill(0);
  const center = Math.floor(count / 2);

  // Pulse radius based on volume
  const maxRadius = Math.floor(volume * center);
  const fadeFactor = 0.8; // trailing fade multiplier

  for (let r = 0; r <= maxRadius; r++) {
    const left = center - r;
    const right = center + r;

    const brightness = Math.pow(fadeFactor, r); // fade trail
    const waveHue = (hue + r / count) % 1.0;
    const [rVal, gVal, bVal] = hsvToRgb(waveHue, 1, brightness);

    if (left >= 0) {
      leds[left * 3] = rVal;
      leds[left * 3 + 1] = gVal;
      leds[left * 3 + 2] = bVal;
    }
    if (right < count) {
      leds[right * 3] = rVal;
      leds[right * 3 + 1] = gVal;
      leds[right * 3 + 2] = bVal;
    }
  }

  return Buffer.from([0x02, 0x01, ...leds]);
}

function renderPacketLinearWhite(count, volume) {
  const lit = Math.floor(volume * count);
  const leds = [];

  for (let i = 0; i < count; i++) {
    if (i < lit) {
      leds.push(255, 255, 255); // White color
    } else {
      leds.push(0, 0, 0);
    }
  }

  return Buffer.from([0x02, 0x01, ...leds]);
}




function renderPacket(count, volume, hue, effect) {
  switch (effect) {
    case 'linear-white': return renderPacketLinearWhite(count, volume);
    case 'center-pulse': return renderPacketCenterPulse(count, volume, hue);
    case 'rainbow-flow': return renderPacketRainbowFlow(count, volume, hue);
    case 'wave-pulse': return renderPacketWavePulseFlow(count, volume, hue);
    default: return renderPacketLinear(count, volume, hue);
  }
}

// === WebSocket Server ===
const wss = new WebSocket.Server({ port: 3001 }, () =>
  console.log('WebSocket server running on ws://localhost:3001')
);

wss.on('connection', (ws) => {
  console.log('Client connected');

  // Send current state to client
  ws.send(JSON.stringify({
    type: 'state',
    enabled: isEnabled,
    effect: currentEffect,
  }));

  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data);

      if (msg.action === 'toggle') {
        isEnabled = !!msg.enabled;
        console.log(`🔁 Visualizer ${isEnabled ? 'ENABLED' : 'DISABLED'}`);
      } else if (msg.action === 'set-effect' && typeof msg.effect === 'string') {
        currentEffect = msg.effect;
        console.log(`🎨 Effect changed to: ${currentEffect}`);
      } else if (msg.action === 'update' && isEnabled) {
        const { volume, hue } = msg;
        for (const dev of LED_DEVICES) {
          const pkt = renderPacket(dev.count, volume, hue, currentEffect);
          udpSocket.send(pkt, 0, pkt.length, 21324, dev.ip);
        }
      }
    } catch (err) {
      console.error('❌ Invalid message:', err);
    }
  });

  ws.on('close', () => {
    console.log('❌ Client disconnected');
  });
});
