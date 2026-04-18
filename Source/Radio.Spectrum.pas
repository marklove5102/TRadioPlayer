unit Radio.Spectrum;

interface

uses
  System.Classes,
  System.Math,
  System.SysUtils,
  Radio.Output,
  Radio.Types;

type
  TRadioSpectrumAnalyzer = class
  private
    FBinCount: Integer;
    FBufferedSamples: Integer;
    FChannels: Integer;
    FFFTSize: Integer;
    FLastEmitTick: Cardinal;
    FMinFrequencyHz: Single;
    FOutput: TArray<Single>;
    FReal: TArray<Double>;
    FImag: TArray<Double>;
    FRing: TArray<Single>;
    FSampleRate: Integer;
    FWindow: TArray<Double>;
    FWritePos: Integer;
    procedure AddSample(const Value: Single);
    procedure BuildWindow;
    procedure CopyLatestSamples(var Samples: TArray<Single>);
    procedure EnsureConfigured(SampleRate, Channels: Integer);
    procedure PerformFFT;
    procedure ReverseBits(var RealData, ImagData: TArray<Double>);
  public
    constructor Create(AFFTSize, ABinCount: Integer);
    function Consume(Buffer: PByte; ByteCount, Channels, SampleRate: Integer;
      SampleType: TAudioSampleType; MinIntervalMS: Cardinal;
      OutputLatencyMS, QueueDurationMS: Integer; out Spectrum: TRadioSpectrumData): Boolean;
    property BinCount: Integer read FBinCount;
    property FFTSize: Integer read FFFTSize;
    property MinFrequencyHz: Single read FMinFrequencyHz write FMinFrequencyHz;
  end;

implementation

constructor TRadioSpectrumAnalyzer.Create(AFFTSize, ABinCount: Integer);
begin
  inherited Create;
  if AFFTSize < 256 then
    AFFTSize := 256;
  if (AFFTSize and (AFFTSize - 1)) <> 0 then
    raise Exception.Create('FFT size must be a power of two');
  if ABinCount < 8 then
    ABinCount := 8;

  FFFTSize := AFFTSize;
  FBinCount := ABinCount;
  FMinFrequencyHz := 40.0;
  SetLength(FRing, FFFTSize);
  SetLength(FWindow, FFFTSize);
  SetLength(FReal, FFFTSize);
  SetLength(FImag, FFFTSize);
  SetLength(FOutput, FBinCount);
  BuildWindow;
end;

procedure TRadioSpectrumAnalyzer.AddSample(const Value: Single);
begin
  FRing[FWritePos] := EnsureRange(Value, -1.0, 1.0);
  Inc(FWritePos);
  if FWritePos >= FFFTSize then
    FWritePos := 0;
  if FBufferedSamples < FFFTSize then
    Inc(FBufferedSamples);
end;

procedure TRadioSpectrumAnalyzer.BuildWindow;
var
  I: Integer;
begin
  for I := 0 to FFFTSize - 1 do
    FWindow[I] := 0.5 * (1.0 - Cos((2.0 * Pi * I) / (FFFTSize - 1)));
end;

function TRadioSpectrumAnalyzer.Consume(Buffer: PByte; ByteCount, Channels, SampleRate: Integer;
  SampleType: TAudioSampleType; MinIntervalMS: Cardinal; OutputLatencyMS, QueueDurationMS: Integer;
  out Spectrum: TRadioSpectrumData): Boolean;
var
  FrameCount: Integer;
  I: Integer;
  LeftValue: Single;
  MonoValue: Single;
  NowTick: Cardinal;
  RightValue: Single;
  Samples: TArray<Single>;
  Sample16: PSmallInt;
  Sample32: PSingle;
  BinHigh: Integer;
  BinLow: Integer;
  BinStartHz: Double;
  BinEndHz: Double;
  FrequencyStep: Double;
  MaxMagnitude: Double;
  Magnitude: Double;
  Nyquist: Double;
  SpectrumBin: Integer;
  FFTBin: Integer;
  FFTLimit: Integer;
begin
  Result := False;
  if (SampleRate <= 0) or (Channels <= 0) or (ByteCount <= 0) or not Assigned(Buffer) then
    Exit;

  EnsureConfigured(SampleRate, Channels);

  case SampleType of
    astFloat32:
      begin
        FrameCount := ByteCount div (Channels * SizeOf(Single));
        if FrameCount <= 0 then
          Exit;
        Sample32 := PSingle(Buffer);
        for I := 0 to FrameCount - 1 do
        begin
          LeftValue := EnsureRange(Sample32^, -1.0, 1.0);
          Inc(Sample32);
          if Channels > 1 then
          begin
            RightValue := EnsureRange(Sample32^, -1.0, 1.0);
            Inc(Sample32);
          end
          else
            RightValue := LeftValue;
          MonoValue := 0.5 * (LeftValue + RightValue);
          AddSample(MonoValue);
          Inc(Sample32, Channels - Min(Channels, 2));
        end;
      end;
  else
    begin
      FrameCount := ByteCount div (Channels * SizeOf(SmallInt));
      if FrameCount <= 0 then
        Exit;
      Sample16 := PSmallInt(Buffer);
      for I := 0 to FrameCount - 1 do
      begin
        LeftValue := Sample16^ / 32768.0;
        Inc(Sample16);
        if Channels > 1 then
        begin
          RightValue := Sample16^ / 32768.0;
          Inc(Sample16);
        end
        else
          RightValue := LeftValue;
        MonoValue := 0.5 * (LeftValue + RightValue);
        AddSample(MonoValue);
        Inc(Sample16, Channels - Min(Channels, 2));
      end;
    end;
  end;

  if FBufferedSamples < FFFTSize then
    Exit;

  NowTick := TThread.GetTickCount;
  if (MinIntervalMS > 0) and (NowTick - FLastEmitTick < MinIntervalMS) then
    Exit;
  FLastEmitTick := NowTick;

  CopyLatestSamples(Samples);
  for I := 0 to FFFTSize - 1 do
  begin
    FReal[I] := Samples[I] * FWindow[I];
    FImag[I] := 0;
  end;
  PerformFFT;

  Nyquist := FSampleRate * 0.5;
  FrequencyStep := FSampleRate / FFFTSize;
  FFTLimit := (FFFTSize div 2) - 1;
  for SpectrumBin := 0 to FBinCount - 1 do
  begin
    BinStartHz := Exp(Ln(FMinFrequencyHz) +
      (Ln(Nyquist) - Ln(FMinFrequencyHz)) * (SpectrumBin / FBinCount));
    BinEndHz := Exp(Ln(FMinFrequencyHz) +
      (Ln(Nyquist) - Ln(FMinFrequencyHz)) * ((SpectrumBin + 1) / FBinCount));
    BinLow := Max(1, Floor(BinStartHz / FrequencyStep));
    BinHigh := Min(FFTLimit, Ceil(BinEndHz / FrequencyStep));
    if BinHigh < BinLow then
      BinHigh := BinLow;

    MaxMagnitude := 0;
    for FFTBin := BinLow to BinHigh do
    begin
      Magnitude := Sqrt(Sqr(FReal[FFTBin]) + Sqr(FImag[FFTBin]));
      if Magnitude > MaxMagnitude then
        MaxMagnitude := Magnitude;
    end;

    if MaxMagnitude > 0 then
    begin
      MaxMagnitude := MaxMagnitude / (FFFTSize * 0.5);
      FOutput[SpectrumBin] := EnsureRange((20 * Log10(MaxMagnitude + 1.0E-9) + 72) / 72, 0.0, 1.0);
    end
    else
      FOutput[SpectrumBin] := 0;
  end;

  Spectrum.CaptureTickMS := NowTick;
  Spectrum.SampleRate := FSampleRate;
  Spectrum.Channels := FChannels;
  Spectrum.FFTSize := FFFTSize;
  Spectrum.BinHz := FrequencyStep;
  Spectrum.OutputLatencyMS := OutputLatencyMS;
  Spectrum.QueueDurationMS := QueueDurationMS;
  Spectrum.TotalLatencyMS := OutputLatencyMS + QueueDurationMS;
  SetLength(Spectrum.Bins, FBinCount);
  Move(FOutput[0], Spectrum.Bins[0], FBinCount * SizeOf(Single));
  Result := True;
end;

procedure TRadioSpectrumAnalyzer.CopyLatestSamples(var Samples: TArray<Single>);
var
  Count: Integer;
  I: Integer;
  ReadPos: Integer;
begin
  Count := FFFTSize;
  SetLength(Samples, Count);
  ReadPos := FWritePos;
  for I := 0 to Count - 1 do
  begin
    Samples[I] := FRing[ReadPos];
    Inc(ReadPos);
    if ReadPos >= FFFTSize then
      ReadPos := 0;
  end;
end;

procedure TRadioSpectrumAnalyzer.EnsureConfigured(SampleRate, Channels: Integer);
begin
  if (FSampleRate <> SampleRate) or (FChannels <> Channels) then
  begin
    FSampleRate := SampleRate;
    FChannels := Channels;
    FBufferedSamples := 0;
    FWritePos := 0;
    FLastEmitTick := 0;
    FillChar(FRing[0], Length(FRing) * SizeOf(Single), 0);
  end;
end;

procedure TRadioSpectrumAnalyzer.PerformFFT;
var
  Angle: Double;
  HalfSize: Integer;
  I: Integer;
  J: Integer;
  K: Integer;
  Step: Integer;
  TempImag: Double;
  TempReal: Double;
  TwiddleImag: Double;
  TwiddleReal: Double;
  UImag: Double;
  UReal: Double;
begin
  ReverseBits(FReal, FImag);
  HalfSize := 1;
  while HalfSize < FFFTSize do
  begin
    Step := HalfSize * 2;
    Angle := -Pi / HalfSize;
    for I := 0 to HalfSize - 1 do
    begin
      UReal := Cos(Angle * I);
      UImag := Sin(Angle * I);
      J := I;
      while J < FFFTSize do
      begin
        K := J + HalfSize;
        TwiddleReal := (UReal * FReal[K]) - (UImag * FImag[K]);
        TwiddleImag := (UReal * FImag[K]) + (UImag * FReal[K]);

        TempReal := FReal[J];
        TempImag := FImag[J];

        FReal[K] := TempReal - TwiddleReal;
        FImag[K] := TempImag - TwiddleImag;
        FReal[J] := TempReal + TwiddleReal;
        FImag[J] := TempImag + TwiddleImag;

        Inc(J, Step);
      end;
    end;
    HalfSize := Step;
  end;
end;

procedure TRadioSpectrumAnalyzer.ReverseBits(var RealData, ImagData: TArray<Double>);
var
  Bit: Integer;
  I: Integer;
  J: Integer;
  Temp: Double;
begin
  J := 0;
  for I := 0 to FFFTSize - 2 do
  begin
    if I < J then
    begin
      Temp := RealData[I];
      RealData[I] := RealData[J];
      RealData[J] := Temp;
      Temp := ImagData[I];
      ImagData[I] := ImagData[J];
      ImagData[J] := Temp;
    end;
    Bit := FFFTSize shr 1;
    while (Bit > 0) and ((J and Bit) <> 0) do
    begin
      J := J and not Bit;
      Bit := Bit shr 1;
    end;
    J := J or Bit;
  end;
end;

end.
