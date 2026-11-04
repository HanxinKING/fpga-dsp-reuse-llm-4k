"""Separate Q9 generated reasoning from the answer after an open think prefix."""

def split_thinking(raw):
    if not isinstance(raw,str):raise ValueError('Thinking 输出格式无效')
    value=raw
    for suffix in ('<|im_end|>','<|endoftext|>'):
        value=value.replace(suffix,'')
    if value.startswith('<think>'):value=value[len('<think>'):]
    reasoning,separator,answer=value.partition('</think>')
    return dict(thinking_text=reasoning.strip(),thinking_complete=bool(separator),
                answer_text=answer.strip() if separator else '')


def decorate_turn(turn,tokenizer,ids):
    raw=tokenizer.decode(ids,skip_special_tokens=False)
    parts=split_thinking(raw)
    turn.update(thinking=True,raw_text=raw,**parts)
    turn['text']=parts['answer_text']

