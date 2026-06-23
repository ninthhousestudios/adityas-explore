import 'chart_wheel_layout.dart';

enum UncertainKind { trimsamsa, hora }

typedef BeingRef = ({String name, String type, String planet, int sign});

sealed class PopupState {}

class BeingFromPlanet extends PopupState {
  final PlacedPlanet planet;
  BeingFromPlanet(this.planet);
}

class BeingFromName extends PopupState {
  final BeingRef being;
  BeingFromName(this.being);
}

class BeingTypePopup extends PopupState {
  final String type;
  BeingTypePopup(this.type);
}

class PlanetPopup extends PopupState {
  final String planet;
  PlanetPopup(this.planet);
}

class UncertaintyPopup extends PopupState {
  final String planet;
  final UncertainKind kind;
  UncertaintyPopup(this.planet, this.kind);
}
