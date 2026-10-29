import Foundation

// A focused WebMIDI bridge informed by MIDIWeb's port-map, document-start and
// explicit SysEx permission lessons. No browser UI or USB code is included.
enum WebMIDIPolyfill {
    static let source = #"""
    (() => {
      if (location.origin !== 'https://pixels.cymaforma.com') return;
      const pending = new Map(), accesses = new Set();
      let serial = 0, snapshot = {inputs:[], outputs:[]};
      function post(value) { window.webkit.messageHandlers.rndmidi.postMessage(value); }
      class MIDIMessageEvent extends Event {
        constructor(type, options) { super(type); this.data = new Uint8Array(options.data); this.receivedTime = options.receivedTime ?? performance.now(); }
      }
      class MIDIConnectionEvent extends Event {
        constructor(type, options) { super(type); this.port = options.port; }
      }
      class MIDIPort extends EventTarget {
        constructor(info, type, access) {
          super(); Object.assign(this,info); this.type = type; this.manufacturer = 'cyma forma'; this.version = ''; this.state = 'connected'; this.connection = 'closed'; this.access = access;
          this.onstatechange = null; this.onmidimessage = null;
        }
        async open() { this.connection = 'open'; this.changed(); return this; }
        async close() { this.connection = 'closed'; if(this.type === 'output') this.clear(); this.changed(); return this; }
        clear() { post({type:'clear', port:this.id}); }
        changed() {
          const event = new MIDIConnectionEvent('statechange',{port:this});
          this.dispatchEvent(event); this.onstatechange?.(event);
          this.access.dispatchEvent(new MIDIConnectionEvent('statechange',{port:this})); this.access.onstatechange?.(event);
        }
        send(input, timestamp=0) {
          if(this.state !== 'connected') throw new DOMException('Device disconnected','InvalidStateError');
          const data = Array.from(input);
          if(data.some(x=>!Number.isInteger(x)||x<0||x>255)) throw new TypeError('Invalid MIDI bytes');
          if(data.includes(240) && !this.access.sysexEnabled) throw new DOMException('SysEx denied','InvalidAccessError');
          this.connection = 'open';
          post({type:'send', port:this.id, data, delay:Math.max(0,Number(timestamp)-performance.now())});
        }
        get [Symbol.toStringTag]() { return this.type === 'input' ? 'MIDIInput' : 'MIDIOutput'; }
      }
      class MIDIAccess extends EventTarget {
        constructor(sysex) { super(); this.sysexEnabled=sysex; this.inputs=new Map(); this.outputs=new Map(); this.onstatechange=null; this.update(); }
        update() {
          for(const [kind,type] of [['inputs','input'],['outputs','output']]) {
            const map=this[kind], wanted=new Set(snapshot[kind].map(x=>x.id));
            for(const [id,port] of map) if(!wanted.has(id)) { port.state='disconnected'; port.connection='closed'; port.changed(); map.delete(id); }
            for(const info of snapshot[kind]) if(!map.has(info.id)) { const port=new MIDIPort(info,type,this); map.set(info.id,port); port.changed(); }
          }
        }
        get [Symbol.toStringTag]() { return 'MIDIAccess'; }
      }
      Object.assign(window,{MIDIAccess,MIDIPort,MIDIInput:MIDIPort,MIDIOutput:MIDIPort,MIDIMessageEvent,MIDIConnectionEvent});
      navigator.requestMIDIAccess = options => new Promise((resolve,reject)=> {
        const id=String(++serial); pending.set(id,{resolve,reject}); post({type:'access', id, sysex:!!options?.sysex});
      });
      window.__rndbuddy = {
        access(id,granted,sysex,ports) {
          const request=pending.get(id); if(!request) return; pending.delete(id);
          if(!granted) { request.reject(new DOMException('MIDI permission denied','NotAllowedError')); return; }
          snapshot=ports; const access=new MIDIAccess(sysex); accesses.add(access); request.resolve(access);
        },
        ports(ports) { snapshot=ports; for(const access of accesses) access.update(); },
        receive(id,data,age) {
          for(const access of accesses) {
            if(data[0]===240 && !access.sysexEnabled) continue;
            const port=access.inputs.get(id); if(!port) continue;
            const event=new MIDIMessageEvent('midimessage',{data,receivedTime:performance.now()-Math.max(0,age)});
            port.dispatchEvent(event); port.onmidimessage?.(event);
          }
        }
      };
    })();
    """#
}
