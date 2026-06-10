/**
 * RIDDIIM Neural Engine v1.6
 * Sovereign Signal Processor - High Fidelity Update
 */

class NeuralEngine {
  constructor() {
    this.audioCtx = null;
    this.analyser = null;
    this.microphone = null;
    this.isProcessing = false;
    this.signalData = [];
  }

  async startAnalysis() {
    try {
      if (!this.audioCtx) {
        this.audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      }
      
      if (this.audioCtx.state === 'suspended') {
        await this.audioCtx.resume();
      }

      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      this.microphone = this.audioCtx.createMediaStreamSource(stream);
      this.analyser = this.audioCtx.createAnalyser();
      this.analyser.fftSize = 256;
      this.microphone.connect(this.analyser);
      
      this.isProcessing = true;
      this.signalData = [];
      
      // Initialize Canvas size
      const canvas = document.getElementById('neural-canvas');
      if(canvas) {
        canvas.width = canvas.offsetWidth * window.devicePixelRatio;
        canvas.height = canvas.offsetHeight * window.devicePixelRatio;
      }

      this.processFrame();
      
      return new Promise((resolve) => {
        setTimeout(() => {
          this.stopAnalysis();
          resolve(this.calculateSignature());
        }, 5000);
      });
    } catch (err) {
      console.error('NEURAL_SIGNAL_FAILURE:', err);
      return null;
    }
  }

  processFrame() {
    if (!this.isProcessing) return;
    const dataArray = new Uint8Array(this.analyser.frequencyBinCount);
    this.analyser.getByteFrequencyData(dataArray);
    
    let maxVal = 0;
    let maxIdx = 0;
    for (let i = 0; i < dataArray.length; i++) {
      if (dataArray[i] > maxVal) {
        maxVal = dataArray[i];
        maxIdx = i;
      }
    }
    
    // Always draw for UX feedback
    this.drawCanvas(dataArray);
    
    // Only capture signal if above threshold
    if (maxVal > 30) { 
      this.signalData.push(maxIdx);
    }
    
    requestAnimationFrame(() => this.processFrame());
  }

  drawCanvas(data) {
    const canvas = document.getElementById('neural-canvas');
    if(!canvas) return;
    const ctx = canvas.getContext('2d');
    const w = canvas.width;
    const h = canvas.height;
    
    ctx.clearRect(0, 0, w, h);
    
    const barW = w / data.length;
    for(let i=0; i<data.length; i++) {
      const barH = (data[i] / 255) * h;
      // Gradient for high-fidelity look
      const grad = ctx.createLinearGradient(0, h, 0, h - barH);
      grad.addColorStop(0, 'rgba(255, 255, 255, 0.1)');
      grad.addColorStop(1, 'rgba(255, 255, 255, 0.8)');
      
      ctx.fillStyle = grad;
      ctx.fillRect(i * barW, h - barH, barW - 2, barH);
    }
  }

  stopAnalysis() {
    this.isProcessing = false;
    if (this.microphone) {
      this.microphone.mediaStream.getTracks().forEach(t => t.stop());
      this.microphone.disconnect();
    }
  }

  calculateSignature() {
    if (this.signalData.length < 5) return 'UNKNOWN_SIGNAL';
    
    const avg = this.signalData.reduce((a, b) => a + b, 0) / this.signalData.length;
    
    if (avg < 15) return 'deep bass soul';
    if (avg < 40) return 'lo-fi acoustic chill';
    if (avg < 70) return 'synth pop wave';
    if (avg < 100) return 'vibrant afrobeat';
    return 'high frequency dance';
  }
}

window.NeuralEngine = new NeuralEngine();
