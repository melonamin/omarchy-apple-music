BEGIN {
  pi = atan2(0, -1)
  bandCount = bars > 0 ? int(bars) : 32
  sampleRate = rate > 0 ? rate : 24000
  lowFrequency = 55
  highFrequency = 9000
  logRange = log(highFrequency / lowFrequency)
  revision = 0

  for (band = 1; band <= bandCount; band++) {
    position = (band - 1) / (bandCount - 1)
    frequency = lowFrequency * exp(logRange * position)
    bandPosition[band] = position
    coefficient[band] = 2 * cos(2 * pi * frequency / sampleRate)
    smoothed[band] = 0
  }
}

function clamp(value, minimum, maximum) {
  if (value < minimum) return minimum
  if (value > maximum) return maximum
  return value
}

function publish(    json, band) {
  revision++
  json = "{\"schemaVersion\":1,\"active\":true,\"revision\":" revision ",\"bands\":["
  for (band = 1; band <= bandCount; band++) {
    if (band > 1) json = json ","
    json = json sprintf("%.3f", smoothed[band])
  }
  json = json "]}"

  if (output == "-") {
    print json
    fflush()
  } else {
    print json > output
    close(output)
  }
}

NF > 8 {
  sampleCount = NF
  for (sampleIndex = 1; sampleIndex <= sampleCount; sampleIndex++) {
    window = 0.5 - 0.5 * cos(2 * pi * (sampleIndex - 1) / (sampleCount - 1))
    samples[sampleIndex] = ($sampleIndex / 32768) * window
  }

  for (band = 1; band <= bandCount; band++) {
    previous = 0
    previousPrevious = 0
    for (sampleIndex = 1; sampleIndex <= sampleCount; sampleIndex++) {
      current = samples[sampleIndex] + coefficient[band] * previous - previousPrevious
      previousPrevious = previous
      previous = current
    }

    power = previousPrevious * previousPrevious + previous * previous - coefficient[band] * previous * previousPrevious
    magnitude = sqrt(clamp(power, 0, 1e12)) / sampleCount
    decibels = 20 * log(magnitude + 1e-9) / log(10)
    decibels += bandPosition[band] * 18
    level = clamp((decibels + 68) / 56, 0, 1)
    level = sqrt(level)

    if (level > smoothed[band]) smoothed[band] += (level - smoothed[band]) * 0.74
    else smoothed[band] += (level - smoothed[band]) * 0.2
  }

  publish()
}
