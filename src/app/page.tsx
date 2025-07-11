'use client';
import styles from './page.module.css';
import { useEffect, useRef, useState } from 'react';


const EFFECTS = [
  { value: 'linear-white', label: 'Linear White' },
  { value: 'linear-fill', label: 'Linear Fill' },
  { value: 'center-pulse', label: 'Center Pulse' },
  { value: 'rainbow-flow', label: 'Rainbow Flow' },
  { value: 'wave-pulse', label: 'Wave Pulse Flow' },
];


export default function HomePage() {
  const socketRef = useRef<WebSocket | null>(null);
  const analyserRef = useRef<AnalyserNode | null>(null);
  const animationRef = useRef<number | null>(null);

  const [isEnabled, setIsEnabled] = useState(false);
  const [selectedEffect, setSelectedEffect] = useState('linear-fill');

  // Setup WebSocket once
  useEffect(() => {
    const socket = new WebSocket(`ws://${window.location.hostname}:3001`);

    socketRef.current = socket;

    socket.onmessage = (event) => {
      const data = JSON.parse(event.data);
      if (data.type === 'state') {
        setIsEnabled(data.enabled);
        setSelectedEffect(data.effect);
      }
    };

    return () => {
      socket.close();
    };
  }, []);

  // Send toggle
  const sendToggle = (enabled: boolean) => {
    socketRef.current?.send(JSON.stringify({ action: 'toggle', enabled }));
  };

  // Send effect
  const sendEffect = (effect: string) => {
    socketRef.current?.send(JSON.stringify({ action: 'set-effect', effect }));
  };

  // Start audio stream
  useEffect(() => {
    if (!isEnabled) {
      if (animationRef.current) cancelAnimationFrame(animationRef.current);
      return;
    }

    const start = async () => {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const audioCtx = new AudioContext();
      const source = audioCtx.createMediaStreamSource(stream);
      const analyser = audioCtx.createAnalyser();
      analyser.fftSize = 256;
      const dataArray = new Uint8Array(analyser.frequencyBinCount);
      analyserRef.current = analyser;
      source.connect(analyser);

      const loop = () => {
        if (!socketRef.current || socketRef.current.readyState !== WebSocket.OPEN) return;
        analyser.getByteFrequencyData(dataArray);
        const volume = dataArray.slice(1, 20).reduce((a, b) => a + b, 0) / (20 * 255);
        const hue = (Date.now() * 0.0001) % 1;

        socketRef.current.send(JSON.stringify({
          action: 'update',
          volume,
          hue,
        }));

        animationRef.current = requestAnimationFrame(loop);
      };

      loop();
    };

    start();
  }, [isEnabled]);

  return (
    <main className={styles.main}>
      <h1 className={styles.title}>🎶 LED UDP Visualizer</h1>

      <div className={styles.controls}>
        <button
          onClick={() => {
            const next = !isEnabled;
            setIsEnabled(next);
            sendToggle(next);
          }}
          className={`${styles.button} ${isEnabled ? styles.buttonEnabled : ''}`}
        >
          {isEnabled ? '🛑 Stop Visualizer' : '▶️ Start Visualizer'}
        </button>

        <select
          value={selectedEffect}
          onChange={(e) => {
            const effect = e.target.value;
            setSelectedEffect(effect);
            sendEffect(effect);
          }}
          className={styles.select}
        >
          {EFFECTS.map((e) => (
            <option key={e.value} value={e.value}>{e.label}</option>
          ))}
        </select>
      </div>

      <p className={styles.selectedEffect}>
        Selected Effect: <strong>{selectedEffect}</strong>
      </p>
    </main>
  );
}
