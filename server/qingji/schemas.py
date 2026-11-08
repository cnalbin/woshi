from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, SecretStr, StrictBool, StrictFloat, StrictInt, model_validator

Number = Annotated[StrictFloat, Field(allow_inf_nan=False)]
PhotoName = Annotated[str, Field(pattern=r"^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}\.jpg$")]
Digest = Annotated[str, Field(pattern=r"^[a-f0-9]{64}$")]


class Model(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class LoginInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    username: str = Field(min_length=3, max_length=64)
    password: SecretStr = Field(min_length=1, max_length=128)


class ProfileInput(Model):
    sex: Literal["male", "female"]
    age: Annotated[StrictInt, Field(ge=18, le=100)]
    heightCM: Annotated[Number, Field(ge=100, le=230)]
    weightKG: Annotated[Number, Field(ge=25, le=300)]


class Profile(ProfileInput):
    dailyTarget: Annotated[Number, Field(ge=800, le=6000)]


class MetabolismResult(Model):
    estimatedKcal: Annotated[Number, Field(ge=600, le=5000)]
    summary: str = Field(min_length=1, max_length=600)
    assumptions: list[Annotated[str, Field(min_length=1, max_length=300)]] = Field(max_length=8)


class Assessment(Model):
    response: MetabolismResult
    profileFingerprint: str = Field(min_length=1, max_length=200)
    createdAt: Number


class Food(Model):
    id: UUID
    name: str = Field(min_length=1, max_length=80)
    grams: Annotated[Number, Field(gt=0, le=10000)] | None = None
    kcal: Annotated[Number, Field(ge=0, le=10000)]


class Meal(Model):
    id: UUID
    consumedAt: Number
    kind: Literal["breakfast", "lunch", "dinner", "snack"]
    items: list[Food] = Field(min_length=1, max_length=30)
    source: Literal["manual", "ai"]
    summary: str = Field(default="", max_length=600)
    assumptions: list[Annotated[str, Field(max_length=300)]] = Field(default_factory=list, max_length=8)
    photoFilename: PhotoName | None = None
    createdAt: Number


class ActivityDay(Model):
    id: str = Field(min_length=1, max_length=160)
    day: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$")
    timeZone: str = Field(min_length=1, max_length=100)
    activeKcal: Annotated[Number, Field(ge=0, le=30000)]
    updatedAt: Number


class Snapshot(Model):
    schemaVersion: Literal[1] = 1
    profile: Profile | None = None
    metabolism: Assessment | None = None
    meals: list[Meal] = Field(default_factory=list, max_length=10000)
    activityDays: list[ActivityDay] = Field(default_factory=list, max_length=20000)
    # Permission is device-specific and deliberately not restored on another phone.
    aiConsent: StrictBool = False

    @model_validator(mode="after")
    def unique_records(self):
        for values in [self.meals, self.activityDays]:
            ids = [str(value.id) for value in values]
            if len(ids) != len(set(ids)):
                raise ValueError("Duplicate record IDs")
        return self


class PhotoReference(Model):
    filename: PhotoName
    sha256: Digest


class BackupWrite(Model):
    expectedRevision: Annotated[StrictInt, Field(ge=0)]
    snapshot: Snapshot
    photos: list[PhotoReference] = Field(default_factory=list, max_length=10000)

    @model_validator(mode="after")
    def complete_manifest(self):
        names = [photo.filename for photo in self.photos]
        expected = {meal.photoFilename for meal in self.snapshot.meals if meal.photoFilename is not None}
        if len(names) != len(set(names)) or set(names) != expected:
            raise ValueError("Photo manifest must exactly match the saved meals")
        return self


class MealInput(Model):
    imageBase64: str = Field(min_length=16, max_length=5_400_000)
    note: str = Field(default="", max_length=500)


class RecognizedFood(Model):
    name: str = Field(min_length=1, max_length=80)
    estimatedGrams: Annotated[Number, Field(gt=0, le=10000)]
    estimatedKcal: Annotated[Number, Field(ge=0, le=10000)]


class MealResult(Model):
    isFood: StrictBool
    items: list[RecognizedFood] = Field(max_length=20)
    summary: str = Field(min_length=1, max_length=600)
    assumptions: list[Annotated[str, Field(min_length=1, max_length=300)]] = Field(max_length=8)
    questions: list[Annotated[str, Field(min_length=1, max_length=300)]] = Field(max_length=8)

    @model_validator(mode="after")
    def food_items(self):
        if self.isFood and not self.items:
            raise ValueError("Food result cannot be empty")
        return self

class RegisterInput(LoginInput):
    password: SecretStr = Field(min_length=12, max_length=128)


class AISettings(Model):
    baseURL: str = Field(default="https://api.deepseek.com", max_length=300)
    textModel: str = Field(default="", max_length=120)
    visionModel: str = Field(default="", max_length=120)
    apiKey: SecretStr = Field(default=SecretStr(""), max_length=500)
