unit Radio.Metadata;

interface

uses
  System.SysUtils,
  Radio.Types;

function StreamMetadataEquals(const A, B: TStreamMetadata): Boolean;

implementation

function StreamMetadataEquals(const A, B: TStreamMetadata): Boolean;
begin
  Result :=
    (A.StationName = B.StationName) and
    (A.StreamTitle = B.StreamTitle) and
    (A.Genre = B.Genre) and
    (A.Description = B.Description) and
    (A.Url = B.Url) and
    (A.ContentType = B.ContentType) and
    (A.CodecName = B.CodecName) and
    (A.Bitrate = B.Bitrate) and
    (A.SampleRate = B.SampleRate) and
    (A.Channels = B.Channels) and
    (A.ResolvedUrl = B.ResolvedUrl);
end;

end.
