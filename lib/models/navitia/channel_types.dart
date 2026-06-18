enum ChannelTypes {
  web("web"),
  sms("sms"),
  email("email"),
  mobile("mobile"),
  notification("notification"),
  twitter("twitter"),
  facebook("facebook"),
  unknownType("unknownType"),
  title("title"),
  beacon("beacon"),
  pids("pids");

  const ChannelTypes(this.value);

  final String? value;
}
