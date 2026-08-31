extends CanvasLayer
class_name OrderPanel
## The order board, two panes: the list on the left, the selected order on the
## right.
##
## **It moves cargo from storage to the dock and no further.** Accepting an
## order puts its crates on the pallet outside; walking them onto the rover is
## still `F` at the rack, with the centre of mass falling out of which slots
## end up occupied. A menu that loaded the rover directly would delete the one
## mechanic the cargo system is built around. See docs/02-Systems/Orders.md.
##
## The panel owns no rules. What is on the board, whether an order can be taken
## and what happens when it is handed back all live in OrderBook; the facility
## spawns and recalls the crates. This draws it.

signal closed

@onready var _root: Control = $Root
@onready var _title: Label = $Root/Frame/Margin/Rows/Header/Title
@onready var _subtitle: Label = $Root/Frame/Margin/Rows/Header/Subtitle
@onready var _list: ItemList = $Root/Frame/Margin/Rows/Panes/Left/List
@onready var _empty_note: Label = $Root/Frame/Margin/Rows/Panes/Left/Empty
@onready var _detail: RichTextLabel = $Root/Frame/Margin/Rows/Panes/Right/Detail
@onready var _action: Button = $Root/Frame/Margin/Rows/Panes/Right/Actions/Action
@onready var _close_button: Button = $Root/Frame/Margin/Rows/Panes/Right/Actions/Close
@onready var _status: Label = $Root/Frame/Margin/Rows/Status

var _facility: Facility
var _codes: Array[int] = []
var _selected := 0
var _open := false


func _ready() -> void:
	add_to_group("order_panel")
	_root.visible = false
	_list.item_selected.connect(_on_item_selected)
	_action.pressed.connect(_on_action_pressed)
	_close_button.pressed.connect(close)
	Orders.changed.connect(_on_orders_changed)


func is_open() -> bool:
	return _open


func open(facility: Facility) -> void:
	if facility == null:
		return
	_facility = facility
	_open = true
	_root.visible = true
	_title.text = facility.display_name.to_upper()
	_refresh()
	# The list takes focus so the board is navigable on a pad and by keyboard,
	# not only with a mouse the astronaut controller normally has captured.
	if not _codes.is_empty():
		_list.grab_focus()
	else:
		_close_button.grab_focus()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	_facility = null
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()


func _on_orders_changed() -> void:
	if _open:
		_refresh()


# --- Drawing ------------------------------------------------------------

func _refresh() -> void:
	if _facility == null:
		return
	var board := Orders.board_for(_facility.facility_id)
	_codes.clear()
	_list.clear()
	for order in board:
		_codes.append(order.code)
		_list.add_item(_row_text(order))
	_empty_note.visible = _codes.is_empty()
	_list.visible = not _codes.is_empty()
	_selected = clampi(_selected, 0, maxi(_codes.size() - 1, 0))
	if not _codes.is_empty():
		_list.select(_selected)
	_subtitle.text = _subtitle_text()
	_draw_detail()


## "217  Core samples          accepted" — the code first, because the code is
## the thing the receipt and the crate will also show.
func _row_text(order: Order) -> String:
	var mark := "  ▸ " if Orders.is_accepted(order.code) else "    "
	return "%d%s%s" % [order.code, mark, order.title]


func _subtitle_text() -> String:
	var taken := Orders.accepted_orders().size()
	var done := Orders.delivered_count()
	return "%d on the board · %d accepted · %d delivered · %.0f cr earned" % [
		_codes.size(), taken, done, Orders.total_paid()
	]


func _draw_detail() -> void:
	var order := _current()
	if order == null:
		_detail.text = ""
		_action.disabled = true
		_action.text = "Accept"
		_status.text = ""
		return

	var accepted := Orders.is_accepted(order.code)
	var progress := Orders.progress(order.code)
	var lines := PackedStringArray()
	lines.append("[b]%s[/b]" % order.title)
	lines.append("[i]Order %d[/i]" % order.code)
	lines.append("")
	if order.blurb != "":
		lines.append(order.blurb)
		lines.append("")
	lines.append("Destination   %s" % Orders.facility_name(order.destination))
	lines.append("Contents      %s" % order.kind_label())
	lines.append("Load          %d %s · %.0f kg total" % [
		order.crates, "crate" if order.crates == 1 else "crates", order.total_mass()
	])
	lines.append("Handling      %s" % order.fragility_label())
	lines.append("Pays          %.0f cr pristine, less for damage" % order.total_value())
	if order.issuer != "":
		lines.append("Issued by     %s" % order.issuer)
	if accepted:
		lines.append("")
		lines.append("[b]Accepted.[/b] %d of %d delivered." % [progress.x, progress.y])
	_detail.text = "\n".join(lines)

	_action.disabled = false
	_action.text = "Hand back" if accepted else "Accept"
	_status.text = _status_text(order, accepted)


## The one line that has to carry the abandonment rule, because it is the one
## thing about this board a player could not guess.
func _status_text(order: Order, accepted: bool) -> String:
	if accepted:
		return ("Handing back returns the cargo here and reconditions it. "
			+ "You will be running the whole leg again.")
	if order.crates > 6:
		return "Larger than the rover's six slots. This is a two-trip order."
	return "Cargo is put on the dock outside. Load it yourself."


func _current() -> Order:
	if _selected < 0 or _selected >= _codes.size():
		return null
	return Orders.get_order(_codes[_selected])


# --- Actions ------------------------------------------------------------

func _on_item_selected(index: int) -> void:
	_selected = index
	_draw_detail()


func _on_action_pressed() -> void:
	var order := _current()
	if order == null or _facility == null:
		return
	if Orders.is_accepted(order.code):
		_hand_back(order)
	else:
		_take(order)


func _take(order: Order) -> void:
	if not Orders.accept(order.code):
		return
	_facility.issue(order)
	print("ORDER %d accepted at %s: %d crate(s) on the dock"
		% [order.code, _facility.facility_id, order.crates])


func _hand_back(order: Order) -> void:
	# The facility takes the shipment back before the board reopens the row, so
	# there is never a moment where the order is offered and its old crates are
	# still lying around waiting to be issued a second time.
	var taken := _facility.recall(order.code)
	Orders.abandon(order.code)
	print("ORDER %d handed back at %s: %d crate(s) recalled and reconditioned"
		% [order.code, _facility.facility_id, taken])
