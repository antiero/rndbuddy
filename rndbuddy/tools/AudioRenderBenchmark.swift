import AVFoundation
import Foundation
@main struct Benchmark {
 static func legacy(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
  let inputs=UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating:input))
  let outputs=UnsafeMutableAudioBufferListPointer(output)
  func sample(channel:Int,frame:Int) -> Float {
   var base=0
   for buffer in inputs {
    let count=Int(buffer.mNumberChannels)
    if channel >= base && channel < base+count, let data=buffer.mData, frame < Int(buffer.mDataByteSize)/max(1,count*4) {
     return data.assumingMemoryBound(to:Float.self)[frame*count+channel-base]
    }
    base += count
   };return 0
  }
  var outputChannel=0
  for buffer in outputs {
   guard let data=buffer.mData else {continue}
   let channels=Int(buffer.mNumberChannels);let count=Int(buffer.mDataByteSize)/max(1,channels*4)
   let samples=data.assumingMemoryBound(to:Float.self)
   for frame in 0..<count {
    for channel in 0..<channels {
     let target=outputChannel+channel
     let value:Float = target < 2 ? sample(channel:target,frame:frame) : 0
     samples[frame*channels+channel]=value*0.4
    }
   };outputChannel += channels
  }
 }
 static func main() throws {
  let layout=AVAudioChannelLayout(layoutTag:kAudioChannelLayoutTag_DiscreteInOrder|6)!
  let input=AVAudioPCMBuffer(pcmFormat:AVAudioFormat(standardFormatWithSampleRate:48000,channelLayout:layout),frameCapacity:512)!
  let output=AVAudioPCMBuffer(pcmFormat:AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!,frameCapacity:512)!
  input.frameLength=512;output.frameLength=512
  for channel in 0..<6 { for frame in 0..<512 {input.floatChannelData![channel][frame]=sin(Float(frame)*0.1)*0.5} }
  let renderer=MacAudioRender(stats:AudioCaptureStats(),recording:AudioRecordingSink(),offset:0,dry:false,rate:48000)
  renderer.gain.store(Float(0.4).bitPattern,ordering:.relaxed)
  var tb=mach_timebase_info_data_t();mach_timebase_info(&tb)
  func measure(_ name:String, _ body:()->Void) {
   for _ in 0..<30 {body()}
   var durations:[Double]=[]
   for _ in 0..<2000 {
    let start=mach_absolute_time();body()
    durations.append(Double(mach_absolute_time()-start)*Double(tb.numer)/Double(tb.denom)/1e6)
   }
   durations.sort()
   print(name,"medianMs",durations[1000],"p95Ms",durations[1900],"maxMs",durations.last!)
  }
  measure("legacy"){legacy(input:input.audioBufferList,output:output.mutableAudioBufferList)}
  measure("vectorised"){renderer.render(input:input.audioBufferList,output:output.mutableAudioBufferList,time:AudioTimeStamp())}
 }
}
