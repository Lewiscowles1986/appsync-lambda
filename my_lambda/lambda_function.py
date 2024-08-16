"""Simple Hello-world lambda."""

def lambda_handler(event, context):
    name = event.get('name', 'World')
    return {
        "message": f"Hello, {name}!"
    }
