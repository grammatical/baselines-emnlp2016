import re
from difflib import ndiff, restore

def edited_tokens(new_tokens, old_tokens):
    try:
        raw_diff = ndiff(new_tokens, old_tokens)
    except:
        return []

    edits = []
    for edit, start, end in __diff_tokens(raw_diff):
        old_edit = ' '.join(restore(edit, 1))
        new_edit = ' '.join(restore(edit, 2))
        edits.append( (old_edit, new_edit, start, end) )

    return edits

def __diff_tokens(raw_diff):
    diffs = __clean_diff(raw_diff)
    actions = __diff_actions(diffs)

    results = []
    pos_shift = 0
    for start, end, mlen, plen in __edition_indexes(actions):
        start_pos = start - pos_shift
        end_pos = start_pos + mlen
        pos_shift += plen
        results.append( (diffs[start:end], start_pos, end_pos) )

    return results

def __edition_indexes(actions):
    indexes = []
    for match in re.finditer(r'(-+)?(\++)|(-+)(\++)?', actions):
        mlen = max(match.end(1) - match.start(1),
                   match.end(3) - match.start(3))
        plen = max(match.end(2) - match.start(2),
                   match.end(4) - match.start(4))
        indexes.append( (match.start(0), match.end(0), mlen, plen) )

    return indexes

def __clean_diff(diff):
    try:
        return [line for line in list(diff) if not line.startswith('?')]
    except:
        return []

def __diff_actions(diffs):
    return ''.join([line[0] for line in diffs])
