%{
  configs: [
    %{
      name: "default",
      checks: %{
        extra: [
          {SfoxCredo.Check.Design.EctoMigrationTimestamps, []},
          {SfoxCredo.Check.Readability.DocFencedCode, []},
          {SfoxCredo.Check.Readability.DocHeadingLevel, []},
          {SfoxCredo.Check.Readability.DocListStyle, []},
          {SfoxCredo.Check.Warning.AvoidAtomToString, []},
          {SfoxCredo.Check.Warning.LoggerMessageInspect, []},
          {SfoxCredo.Check.Warning.LoggerMetadataInspect, []}
        ]
      }
    }
  ]
}
