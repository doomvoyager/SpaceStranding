extends RefCounted
class_name SiteSurvey
## What a relay mast would achieve if it were raised at one particular spot.
##
## The answer to "can I plant it here", asked of ground that is not a site yet.
## Produced by `Lattice.survey_at()`; read by the HUD while you carry a mast,
## and by anything that later wants to refuse a bad placement.
##
## Deliberately a small object rather than a Dictionary. An untyped Dictionary
## poisons `:=` at every call site that reads a field out of it, and the fields
## here are read in a HUD path where that would be quietly annoying forever.

## Was any existing site both close enough and visible? This is the headline —
## everything else is the detail behind it.
var linked := false

## The site the mast would lean on. Not the *nearest* one: the one whose link
## has the most slack in it, because a mast is only as good as its weakest
## reason to work.
var best_id := ""

## Metres of slack in that weakest reason — the smaller of `range_spare` and
## `clearance`. This is the number to show and the number to rank on. Scoring
## on clearance alone picks sites sitting at 44.0 m of a 45 m reach, which stop
## working the moment anything in the scene moves.
var margin := 0.0

## Metres of link range left over to `best_id`.
var range_spare := 0.0

## Smallest gap between the sight line and the ground beneath it, in metres.
var clearance := 0.0

## Where the antenna would end up standing. Ground height plus the mast.
var mast_point := Vector3.ZERO

## No terrain to stand on, or nothing registered to link to. Distinct from
## `linked == false`, which is a real answer: this one means we could not ask.
var unknown := false


## One coarse line for the HUD. The caller decides whether to show it at all.
func summary() -> String:
	if unknown:
		return "no survey data"
	if not linked:
		return "no link from here"
	return "links to %s · %.0f m margin" % [best_id, margin]
