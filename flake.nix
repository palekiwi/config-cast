{
  description = "Cast configuration";

  outputs = { self, ... }: {
    templates.cue-quickstart = {
      path = ./templates/cue-quickstart;
      description = "Minimal cue + opencode setup for cast";
    };

    templates.default = self.templates.cue-quickstart;
  };
}
