# widget_property_builder.gd — shared SDK contract
class_name WidgetPropertyBuilder
extends RefCounted

func add_dynamic_field(p: String, l: String, v: ReactiveDictionary) -> void:
    pass

func add_action_field(p: String, l: String, v: ReactiveDictionary) -> void:
    pass
