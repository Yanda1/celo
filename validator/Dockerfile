FROM python:3.8
ENV PYTHONUNBUFFERED 1

RUN python3 -m pip install --upgrade pip
# Allows docker to cache installed dependencies between builds
COPY ./requirements.txt requirements.txt
RUN pip install -r requirements.txt

# Adds our application code to the image
COPY . code
WORKDIR code

# Run production server
CMD python app.py
